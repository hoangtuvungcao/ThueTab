// QA for a CROSS-SITE front-end (Cloudflare Pages *.pages.dev → API on thuetab.hidev.dev): token auth, no cookies.
// Simulation: front-end on http://localhost:4173, API on http://127.0.0.1:8000 (different sites).
// Prereqs: `VITE_API_BASE=http://127.0.0.1:8000 npx vite build --outDir dist-cross`,
//          `npx vite preview --outDir dist-cross --host localhost --port 4173`, and the API started with
//          PUBLIC_ORIGIN="http://127.0.0.1:8000,http://localhost:4173".
// Uses a temporary account (created via the API, credited via scripts/manage.py, deleted at the end) and the admin.
import { chromium } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const FRONT = process.env.QA_FRONT || 'http://localhost:4173';
const API = process.env.QA_API || 'http://127.0.0.1:8000';
const ROOT = path.resolve('..');
const DOCS = path.join(ROOT, 'docs');
const EMAIL = `qa-cross-${Date.now()}@thuetab.local`;
const PASSWORD = 'QaCross' + Math.random().toString(36).slice(2, 10);
const ADMIN = (() => { const t = fs.readFileSync(path.join(ROOT, 'data/LOCAL_LOGIN.txt'), 'utf8'); return { email: t.match(/Email: (.+)/)[1].trim(), password: t.match(/Password: (.+)/)[1].trim() }; })();
const manage = (...a) => execFileSync(path.join(ROOT, '.venv/bin/python'), ['scripts/manage.py', ...a], { cwd: ROOT, encoding: 'utf8' }).trim();
const problems = [];
const log = (...a) => console.log('•', ...a);

const browser = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', headless: true, args: ['--no-sandbox'] });

async function newPage(label, viewport = { width: 1440, height: 900 }) {
  const ctx = await browser.newContext({ viewport, acceptDownloads: true });
  // Record WebSocket subprotocols and sent messages.
  await ctx.addInitScript(() => {
    const WS = window.WebSocket;
    window.__ws = [];
    window.WebSocket = function (url, protocols) {
      const ws = new WS(url, protocols);
      window.__ws.push({ url, protocols: protocols ? [].concat(protocols).map((p, i) => (i ? '<token>' : p)) : null, sent: [] });
      const entry = window.__ws[window.__ws.length - 1];
      const send = ws.send.bind(ws);
      ws.send = d => { try { entry.sent.push(JSON.parse(d)); } catch {} return send(d); };
      return ws;
    };
    window.WebSocket.prototype = WS.prototype;
    Object.assign(window.WebSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
  });
  const p = await ctx.newPage();
  const apiOrigins = new Set();
  p.on('request', r => { const u = new URL(r.url()); if (u.pathname.startsWith('/api/')) apiOrigins.add(u.origin); });
  p.on('pageerror', e => problems.push(`[${label}] pageerror: ${e.message}`));
  return { ctx, p, apiOrigins };
}
async function uiLogin(p, { email, password }) {
  await p.goto(FRONT, { waitUntil: 'domcontentloaded' });
  await p.getByRole('button', { name: 'Đăng nhập', exact: true }).first().click();
  await p.locator('[name=email]').fill(email);
  await p.locator('[name=password]').fill(password);
  await p.locator('form button[type=submit]').click();
  await p.locator('.topbar').waitFor({ timeout: 10000 });
}
const token = p => p.evaluate(() => localStorage.getItem('tt_token'));

let registered = false;
try {
  const reg = await fetch(API + '/api/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: FRONT, 'X-Forwarded-For': `198.51.100.${1 + Math.floor(Math.random() * 250)}` /* own rate-limit bucket via the trusted local proxy */ }, body: JSON.stringify({ email: EMAIL, password: PASSWORD, name: 'QA khác site' }) });
  if (!reg.ok) throw new Error('register ' + reg.status + ' ' + (await reg.text()));
  registered = true;
  log('registered', EMAIL, '·', manage('credit', '--email', EMAIL, '--amount', '20000', '--reason', 'QA tạm'));

  // ---------- user: login, token, no cookies ----------
  const { ctx, p, apiOrigins } = await newPage('user');
  await uiLogin(p, { email: EMAIL, password: PASSWORD });
  if (!(await token(p))) problems.push('no tt_token in localStorage after login');
  await ctx.clearCookies();
  await p.reload({ waitUntil: 'domcontentloaded' });
  await p.locator('.topbar').waitFor({ timeout: 10000 }).then(() => log('session survives clearing cookies (token auth)')).catch(() => problems.push('session lost after clearing cookies'));

  // JAR upload
  await p.evaluate(() => { location.hash = '/jars'; });
  await p.locator('.dropzone input[type=file]').setInputFiles(path.resolve('qa-fixtures/hello-midlet.jar'));
  await p.getByText('hello-midlet.jar').first().waitFor({ timeout: 10000 });
  log('JAR upload ok');

  // Rent with that game; thumbnail frames (fetched with the Bearer header → blob URLs)
  await p.evaluate(() => { location.hash = '/tabs'; });
  await p.getByRole('button', { name: /^Thuê tab/ }).first().click();
  await p.getByRole('radio', { name: /^1 ngày/ }).click();
  await p.getByLabel('Tên tab').fill('QA khác site');
  await p.getByRole('radio', { name: /hello-midlet\.jar/ }).first().click();
  await p.locator('.modal-foot button[type=submit]').click();
  const card = p.locator('.tab-card', { hasText: 'QA khác site' });
  await card.waitFor({ timeout: 10000 });
  await card.locator('.card-media img.fg[src^="blob:"]').waitFor({ timeout: 45000 }).then(() => log('thumbnail frames load (blob URLs)')).catch(() => problems.push('thumbnail never loaded'));
  await p.screenshot({ path: `${DOCS}/cross-site-tabs.png` });

  // Viewer: WebSocket with ['bearer', token]; keys go over the socket
  await card.getByRole('button', { name: 'Chơi' }).click();
  await p.waitForFunction(() => { const c = document.querySelector('.viewer canvas.screen-media:not([hidden])'); return c && c.width > 0; }, null, { timeout: 45000 })
    .then(() => log('viewer stream frames')).catch(() => problems.push('viewer: no streamed frame'));
  await p.locator('.viewer').getByRole('button', { name: 'Phím 5' }).click();
  await p.waitForTimeout(800);
  const wsInfo = await p.evaluate(() => window.__ws);
  const stream = wsInfo.find(w => w.url.startsWith(API.replace(/^http/, 'ws') + '/api/tabs/'));
  if (!stream) problems.push('no stream WebSocket to the API origin');
  else {
    if (JSON.stringify(stream.protocols) !== JSON.stringify(['bearer', '<token>'])) problems.push('stream subprotocols: ' + JSON.stringify(stream.protocols));
    if (!stream.sent.some(m => m.type === 'key' && m.key === '5')) problems.push('key not sent over the socket');
    else log('stream uses subprotocol bearer; key 5 sent over the socket');
  }
  await p.screenshot({ path: `${DOCS}/cross-site-viewer.png` });
  await p.locator('.v-head').getByRole('button', { name: 'Đóng', exact: true }).click();

  // Share link on the front-end site; viewer without token (?share=)
  await card.getByRole('button', { name: /Thao tác khác/ }).click();
  await p.getByRole('menuitem', { name: 'Chia sẻ' }).click();
  await p.locator('.share-form').getByRole('button', { name: 'Tạo link' }).click();
  const link = (await p.locator('.share-list li .mono').first().innerText()).trim();
  if (!link.startsWith(FRONT + '/#/s/')) problems.push('share link not on the front-end origin: ' + link);
  await p.keyboard.press('Escape');
  const guest = await newPage('share');
  await guest.p.goto(link, { waitUntil: 'domcontentloaded' });
  await guest.p.waitForFunction(() => { const c = document.querySelector('.share-stage canvas.screen-media:not([hidden])'); return c && c.width > 0; }, null, { timeout: 45000 })
    .then(() => log('share page frames (no token)')).catch(() => problems.push('share page: no frames'));
  const gws = await guest.p.evaluate(() => window.__ws);
  if (!gws.some(w => w.url.includes('share=') && !w.protocols)) problems.push('share stream should use ?share= without a token');
  await guest.p.screenshot({ path: `${DOCS}/cross-site-share.png` });
  await guest.ctx.close();

  if ([...apiOrigins].some(o => o !== API)) problems.push('API calls went to: ' + [...apiOrigins].join(', '));

  // Logout clears the token
  await p.locator('.user-btn').click();
  await p.getByRole('menuitem', { name: 'Đăng xuất' }).click();
  await p.locator('.hero h1').waitFor({ timeout: 10000 });
  if (await token(p)) problems.push('token still stored after logout'); else log('logout cleared the token');
  await ctx.close();

  // ---------- admin: CSV export + JAR download as authenticated blob downloads ----------
  const adm = await newPage('admin');
  await uiLogin(adm.p, ADMIN);
  await adm.ctx.clearCookies();
  await adm.p.evaluate(() => { location.hash = '/admin'; });
  await adm.p.getByRole('button', { name: 'Xuất CSV' }).click();
  const csvDl = adm.p.waitForEvent('download', { timeout: 15000 });
  await adm.p.getByRole('menuitem', { name: /Người dùng/ }).click();
  const csv = await csvDl;
  const csvText = fs.readFileSync(await csv.path(), 'utf8');
  if (!csvText.includes('@')) problems.push('CSV export looks empty'); else log('CSV download', csv.suggestedFilename(), `${csvText.split('\n').length - 1} rows`);
  await adm.p.getByRole('tab', { name: /^File JAR/ }).click();
  const jarDl = adm.p.waitForEvent('download', { timeout: 15000 });
  await adm.p.locator('tr', { hasText: 'hello-midlet.jar' }).first().getByRole('button', { name: 'Tải về' }).click();
  const jar = await jarDl;
  const bytes = fs.readFileSync(await jar.path());
  if (bytes.slice(0, 2).toString() !== 'PK') problems.push('downloaded JAR is not a zip'); else log('JAR download', jar.suggestedFilename(), bytes.length + ' bytes');
  await adm.p.locator('.user-btn').click();
  await adm.p.getByRole('menuitem', { name: 'Đăng xuất' }).click();
  await adm.ctx.close();
} catch (e) {
  problems.push(e.message.split('\n')[0]);
} finally {
  if (registered) { try { log(manage('delete-user', '--email', EMAIL)); } catch (e) { problems.push('delete-user: ' + e.message.split('\n')[0]); } }
  await browser.close();
}
if (problems.length) { console.log('\nPROBLEMS:\n' + problems.map(x => '  - ' + x).join('\n')); process.exit(1); }
console.log('\nCross-site (token) QA passed.');
