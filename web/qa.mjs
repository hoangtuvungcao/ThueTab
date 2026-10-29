// End-to-end QA against the running API (serves web/dist). Usage: npm run build && node qa.mjs && node qa-layout.mjs
// Accounts: data/QA_LOGIN.txt (temporary user) and data/LOCAL_LOGIN.txt (admin). One login per role
// (the API allows ~30 logins / 10 min per IP). Never touches the admin's own tabs; restores every setting it edits.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const BASE = process.env.QA_BASE || 'http://127.0.0.1:8000';
const DOCS = path.resolve('../docs');
const cred = f => { const t = fs.readFileSync(path.resolve('../data', f), 'utf8'); return { email: t.match(/Email: (.+)/)[1].trim(), password: t.match(/Password: (.+)/)[1].trim() }; };
const QA = cred('QA_LOGIN.txt'), ADMIN = cred('LOCAL_LOGIN.txt');
const WIDTHS = [1920, 1440, 1024, 768, 390, 360];
const PAGES = ['tabs', 'wall', 'jars', 'wallet', 'plans', 'help', 'account', 'settings', 'download'];
// 60-character Vietnamese name with stacked diacritics, and a very long JAR filename (fixture copy).
const TAB = ('Tab Ữ Ễ Ỗ thử nghiệm tên rất dài để kiểm tra cắt chữ ' + Date.now().toString().slice(-4) + ' ỹỹỹỹỹỹỹỹỹỹ').slice(0, 60);
const LONG_JAR = path.join(os.tmpdir(), 'tro-choi-thu-nghiem-voi-ten-file-cuc-ky-dai-de-kiem-tra-hien-thi-khong-bi-cat-chu-v1.jar');
fs.copyFileSync(path.resolve('qa-fixtures/hello-midlet.jar'), LONG_JAR);
const JAR_NAME = path.basename(LONG_JAR);

const browser = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', headless: true, args: ['--no-sandbox'] });
const problems = [];
const log = (...a) => console.log('•', ...a);
const shot = (page, name, full = true) => page.screenshot({ path: `${DOCS}/${name}.png`, fullPage: full });

const expected = url => /\/api\/(me|tabs|slots|jars|wallet)$|\/frame$|\/stream\?/.test(url);
async function newPage(viewport, label, extra = {}) {
  const ctx = await browser.newContext({ viewport, ...extra });
  await ctx.addInitScript(() => {
    window.__wsSent = [];
    const send = WebSocket.prototype.send;
    WebSocket.prototype.send = function (d) { try { window.__wsSent.push(JSON.parse(d)); } catch {} return send.call(this, d); };
  });
  const page = await ctx.newPage();
  page.on('pageerror', e => problems.push(`[${label}] pageerror: ${e.message}`));
  page.on('console', m => {
    if (m.type() !== 'error') return;
    if (/Failed to load resource|WebSocket connection/.test(m.text()) && expected(m.location().url || '')) return;
    problems.push(`[${label}] console: ${m.text()} ${m.location().url || ''}`);
  });
  return page;
}
async function noOverflow(page, label) {
  const o = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  if (o > 0) problems.push(`[${label}] horizontal overflow ${o}px at ${page.viewportSize().width}px`);
}
// Text clipped by a fixed box (scrollHeight > clientHeight without scrolling) — the "cut diacritics" bug.
async function noClipping(page, label) {
  const bad = await page.evaluate(() => [...document.querySelectorAll('h1,h2,h3,.btn,.badge,.chip,.stat-value,strong')].filter(el => {
    const st = getComputedStyle(el);
    if (st.display === 'none' || !el.offsetParent || st.overflowY === 'auto' || st.overflowY === 'scroll') return false;
    return el.scrollHeight > el.clientHeight + 2 && st.overflow !== 'visible';
  }).slice(0, 5).map(el => `${el.tagName}.${el.className}: "${el.textContent.trim().slice(0, 30)}"`));
  bad.forEach(b => problems.push(`[${label}] vertical clipping ${b}`));
}
async function login(page, { email, password }) {
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.getByRole('button', { name: 'Đăng nhập', exact: true }).first().click();
  await page.locator('[name=email]').fill(email);
  await page.locator('[name=password]').fill(password);
  await page.locator('form button[type=submit]').click();
  await page.locator('.topbar').waitFor({ timeout: 10000 });
  log('logged in as', email);
}
async function visit(page, id, label) {
  await page.evaluate(h => { location.hash = '/' + h; }, id);
  await page.locator('.page-head h1').first().waitFor();
  await page.waitForTimeout(300);
  await noOverflow(page, `${label}:${id}`);
}
const setPref = (page, k, v) => page.evaluate(([k, v]) => fetch('/api/me/prefs', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ [k]: v }) }), [k, v]);
const banned = ['DEV', 'Phiên bản', '512 MB', 'vCPU', 'container', 'worker', 'Giả lập', 'Sắp có', 'Chưa có kênh hỗ trợ'];
async function noSystemInfo(page, label) {
  const text = await page.locator('body').innerText();
  for (const w of banned) if (new RegExp(`\\b${w}\\b`, 'i').test(text)) problems.push(`[${label}] shows "${w}"`);
}

// ---------- guest landing + download ----------
{
  const page = await newPage({ width: 1440, height: 900 }, 'guest');
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.locator('.hero h1').waitFor();
  await noSystemInfo(page, 'landing');
  await shot(page, 'web-landing');
  for (const w of WIDTHS) {
    await page.setViewportSize({ width: w, height: 900 });
    await page.waitForTimeout(250);
    await noOverflow(page, 'landing');
    if (w === 390) await shot(page, 'web-landing-mobile');
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.getByRole('navigation', { name: 'Trang chủ' }).getByRole('link', { name: 'Tải ứng dụng' }).click();
  await page.locator('.page-head h1', { hasText: 'Tải ứng dụng' }).waitFor();
  await shot(page, 'web-download-guest');
  log('landing + guest download ok');
  await page.context().close();
}

// ---------- QA user ----------
const u = await newPage({ width: 1440, height: 960 }, 'user');
await login(u, QA);
await setPref(u, 'theme', 'dark');
for (const id of PAGES) { await visit(u, id, 'user'); await noSystemInfo(u, 'user:' + id); }

await visit(u, 'jars', 'user');
// Leftovers from an interrupted run: stop old QA tabs now, release them at the end.
const api = (p, m = 'GET', b) => u.evaluate(([p, m, b]) => fetch('/api' + p, { method: m, headers: { 'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined }).then(r => r.json().catch(() => ({}))), [p, m, b]);
const isLeftover = t => t.name.startsWith('Tab Ữ Ễ Ỗ thử') && t.name !== TAB;
for (const t of (await api('/tabs')).filter(isLeftover)) await api('/tabs/' + t.id, 'PATCH', { desired: 'stopped' });
await u.locator('.dropzone input[type=file]').setInputFiles(LONG_JAR);
await u.getByText(JAR_NAME).first().waitFor({ timeout: 10000 });
log('uploaded long-named jar');

// Rent with no game → idle → pick the long-named jar → it starts.
await visit(u, 'tabs', 'user');
await u.getByRole('button', { name: /^Thuê tab/ }).first().click();
const slotRadio = u.getByRole('radio', { name: /Dùng slot trống/ });
if (await slotRadio.count()) { await slotRadio.click(); log('renting into a free slot'); } else await u.getByRole('radio', { name: /^1 ngày/ }).click();
await u.getByLabel('Tên tab').fill(TAB);
await u.getByRole('radio', { name: /Chọn game sau/ }).click();
await shot(u, 'web-rent', false);
await u.locator('#rent-form').evaluate(f => f.closest('.modal').querySelector('button[type=submit]').click());
const card = u.locator('.tab-card', { hasText: TAB });
await card.waitFor({ timeout: 10000 });
await card.locator('.badge', { hasText: 'Chưa chọn game' }).waitFor({ timeout: 8000 });
await card.getByRole('button', { name: 'Chọn game' }).first().click();
await u.getByRole('radio', { name: new RegExp(JAR_NAME.slice(0, 30)) }).first().click();
await u.getByRole('button', { name: 'Chạy game này' }).click();
await card.locator('.card-media img.fg').waitFor({ timeout: 45000 }).then(() => log('card thumbnail live')).catch(() => problems.push('card thumbnail never appeared'));
await u.waitForTimeout(1200);
await noClipping(u, 'tabs');
await shot(u, 'web-desktop');

// ---------- viewer: stream, input, rotation ----------
const sent = () => u.evaluate(() => window.__wsSent.splice(0));
// Identical frames are dropped server-side: a still screen streams ~1 fps and shows "Màn hình tĩnh".
// So assert frames keep arriving (or the static label) and the socket stays live — never a fixed high rate.
const meterText = async () => (await u.locator('.stream-meter').innerText()).trim();
async function measureFps(label) {
  const s = [];
  for (let i = 0; i < 3; i++) { await u.waitForTimeout(1000); s.push(await meterText()); }
  log(`${label}: ${s.join(' | ')}`);
  if (s.every(x => /^0 FPS/.test(x))) problems.push(`${label}: no frames for 3 s`);
  if (await u.locator('.screen-msg', { hasText: /Mất kết nối|không chạy/ }).count()) problems.push(`${label}: stream disconnected`);
}
const canvasIs = (w, h, ms = 60000) => u.waitForFunction(([w, h]) => { const c = document.querySelector('.viewer canvas.screen-media:not([hidden])'); return c && c.width === w && c.height === h; }, [w, h], { timeout: ms });
await card.getByRole('button', { name: 'Chơi' }).click();
await canvasIs(240, 320).then(() => log('streamed 240×320')).catch(() => problems.push('viewer: no 240×320 frame'));
await u.locator('.viewer').getByRole('radio', { name: '30', exact: true }).click();
await measureFps('stream @30');
await sent();
await u.locator('.viewer').getByRole('button', { name: 'Phím 5' }).click();
await u.keyboard.press('F1');
await u.getByRole('button', { name: 'Phím mềm phải (F2)' }).click();
const box = await u.locator('.viewer canvas.screen-media').boundingBox();
await u.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
if (!(await u.locator('.ripple').count())) problems.push('no tap ripple');
await u.waitForTimeout(800);
const msgs = await sent();
const keys = msgs.filter(m => m.type === 'key').map(m => m.key).join(',');
if (keys !== '5,F1,F2') problems.push('socket keys: ' + keys);
const tap = msgs.find(m => m.type === 'tap');
if (!tap || Math.abs(tap.x - 120) > 3 || Math.abs(tap.y - 160) > 3) problems.push('tap mapping off: ' + JSON.stringify(tap));
log('socket input ok:', keys, JSON.stringify(tap));
await u.locator('#game-text').fill('hello123');
await u.locator('.v-side-text button[type=submit]').click();
if (!(await sent()).some(m => m.type === 'text' && m.text === 'hello123')) problems.push('text not sent over socket');
await shot(u, 'web-viewer', false);
// Rotate to 320×240 and wait for the stream hello/frames at the new size; taps map to the new size.
await u.locator('.v-foot').getByRole('button', { name: /Màn hình/ }).click();
await u.locator('.v-panel').getByRole('radio', { name: 'Ngang' }).click();
await u.locator('.screen-msg', { hasText: 'Đang xoay' }).waitFor({ timeout: 5000 }).then(() => log('rotating state shown')).catch(() => problems.push('no rotating state'));
await canvasIs(320, 240, 90000).then(() => log('rotated: streamed 320×240')).catch(() => problems.push('rotation: no 320×240 frame'));
await u.waitForTimeout(1500);
const box2 = await u.locator('.viewer canvas.screen-media').boundingBox();
await sent();
await u.mouse.click(box2.x + box2.width / 2, box2.y + box2.height / 2);
await u.waitForTimeout(500);
const tap2 = (await sent()).find(m => m.type === 'tap');
if (!tap2 || Math.abs(tap2.x - 160) > 3 || Math.abs(tap2.y - 120) > 3) problems.push('landscape tap mapping off: ' + JSON.stringify(tap2));
await shot(u, 'web-viewer-landscape-game', false);
await u.getByRole('button', { name: 'Quay về màn dọc' }).click();
await canvasIs(240, 320, 90000).then(() => log('back to portrait 240×320')).catch(() => problems.push('rotation back failed'));
await u.locator('.v-head').getByRole('button', { name: 'Đóng', exact: true }).click();

// ---------- settings, wall, every page × width × theme ----------
await visit(u, 'settings', 'user');
await u.locator('.card', { hasText: 'Giao diện' }).getByRole('radio', { name: 'Sáng' }).click();
await u.waitForFunction(() => document.documentElement.dataset.theme === 'light');
await shot(u, 'web-settings-light');
await u.locator('.card', { hasText: 'Giao diện' }).getByRole('radio', { name: 'Tối' }).click();
await u.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
await shot(u, 'web-settings');
log('settings theme switch ok');
await visit(u, 'download', 'user');
await shot(u, 'web-download');
await visit(u, 'wall', 'user');
await u.locator('.thumb img').first().waitFor({ timeout: 15000 }).catch(() => problems.push('wall: no thumbnail'));
await shot(u, 'web-wall');

for (const theme of ['dark', 'light']) {
  await setPref(u, 'theme', theme);
  await u.reload({ waitUntil: 'networkidle' });
  for (const w of WIDTHS) {
    await u.setViewportSize({ width: w, height: w < 500 ? 844 : 900 });
    for (const id of PAGES) await visit(u, id, `user-${theme}-${w}`);
    await visit(u, 'tabs', `user-${theme}-${w}`);
    await u.waitForTimeout(500);
    await noClipping(u, `tabs-${theme}-${w}`);
    await shot(u, `web-tabs-${w}${theme === 'light' ? '-light' : ''}`);
    if (w === 390) { await visit(u, 'jars', 'user'); await shot(u, `web-jars-390${theme === 'light' ? '-light' : ''}`); }
  }
}
await setPref(u, 'theme', 'dark');
await u.reload({ waitUntil: 'networkidle' });
await u.setViewportSize({ width: 390, height: 844 });
await visit(u, 'tabs', 'user-390');
await shot(u, 'web-mobile');

// ---------- cleanup: stop, wait, release; delete the long jar ----------
await u.setViewportSize({ width: 1440, height: 960 });
await visit(u, 'tabs', 'user');
await card.getByRole('button', { name: /Thao tác khác/ }).click();
await u.getByRole('menuitem', { name: 'Dừng' }).click();
try {
  await card.locator('.badge', { hasText: 'Tạm dừng' }).waitFor({ timeout: 45000 });
  await card.getByRole('button', { name: /Thao tác khác/ }).click();
  await u.getByRole('menuitem', { name: 'Giải phóng tab' }).click();
  await u.getByRole('button', { name: 'Giải phóng tab' }).click();
  await card.waitFor({ state: 'detached', timeout: 10000 });
  await visit(u, 'jars', 'user');
  for (const t of (await api('/tabs')).filter(t => isLeftover(t) && t.desired === 'stopped' && ['stopped', 'expired', 'error'].includes(t.status))) await api('/tabs/' + t.id, 'DELETE');
  for (const j of (await api('/jars')).filter(j => j.filename === JAR_NAME)) await api('/jars/' + j.id, 'DELETE');
  log('tab released, leftovers and long jars deleted');
} catch (e) { problems.push('cleanup: ' + e.message.split('\n')[0]); }
await u.context().close();

// ---------- admin ----------
const adm = await newPage({ width: 1440, height: 960 }, 'admin');
await login(adm, ADMIN);
await visit(adm, 'admin', 'admin');
await adm.locator('.chart svg').first().waitFor({ timeout: 10000 }).catch(() => problems.push('admin: no chart'));
await shot(adm, 'web-admin');
for (const name of ['Người dùng', 'Tab', 'File JAR', 'Đơn nạp', 'Máy chủ', 'Nhật ký']) {
  await adm.getByRole('tab', { name: new RegExp('^' + name) }).click();
  await adm.waitForTimeout(400);
  if (name === 'File JAR' && !(await adm.locator('a[href*="/download"]').count())) problems.push('admin: no JAR download link');
  if (name === 'Người dùng') { await noClipping(adm, 'admin-users'); await shot(adm, 'web-admin-users'); }
}
// Content editor: change the hero title, check the landing, then restore.
await adm.getByRole('tab', { name: /Nội dung/ }).click();
const heroInput = adm.getByLabel('Tiêu đề lớn');
await heroInput.waitFor();
const original = await heroInput.inputValue();
const probe = 'QA tiêu đề ' + Date.now().toString().slice(-5);
await heroInput.fill(probe);
if (!(await adm.locator('.preview-hero h1', { hasText: probe }).count())) problems.push('content: preview not live');
await adm.locator('.save-bar').getByRole('button', { name: 'Lưu' }).click();
await adm.locator('.save-state', { hasText: 'Đã lưu' }).waitFor({ timeout: 8000 }).catch(() => problems.push('content: no "Đã lưu"'));
await shot(adm, 'web-admin-content');
{
  const g = await newPage({ width: 1280, height: 800 }, 'guest2');
  await g.goto(BASE, { waitUntil: 'networkidle' });
  if (!(await g.locator('.hero h1', { hasText: probe }).count())) problems.push('content: landing did not reflect saved hero title');
  else log('landing reflects admin edit');
  await g.context().close();
}
await heroInput.fill(original);
await adm.locator('.save-bar').getByRole('button', { name: 'Lưu' }).click();
await adm.locator('.save-state', { hasText: 'Đã lưu' }).waitFor({ timeout: 8000 });
log('hero title restored');

// Throwaway user: register via API, then reset password and delete it from the user drawer.
const throwaway = `qa-xoa-${Date.now()}@thuetab.local`;
const reg = await adm.evaluate(e => fetch('/api/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: e, password: 'XoaNgay123456', name: 'Người dùng tạm để xoá' }) }).then(r => r.status), throwaway);
if (reg !== 201 && reg !== 200) problems.push('register throwaway: ' + reg);
await adm.evaluate(() => fetch('/api/admin/overview'));
await adm.reload({ waitUntil: 'networkidle' });
await visit(adm, 'admin', 'admin');
await adm.getByRole('tab', { name: /^Người dùng/ }).click();
await adm.getByRole('searchbox', { name: 'Tìm kiếm' }).fill(throwaway);
await adm.locator('tr.clickable', { hasText: throwaway }).click();
await adm.locator('.drawer').waitFor();
await adm.getByRole('button', { name: 'Đặt lại mật khẩu' }).click();
await adm.getByRole('button', { name: 'Tạo mật khẩu tạm' }).click();
await adm.locator('.temp-pass code').waitFor({ timeout: 8000 }).then(() => log('temp password shown once')).catch(() => problems.push('reset password: no temp password'));
await shot(adm, 'web-admin-reset', false);
await adm.getByRole('button', { name: 'Đã lưu mật khẩu' }).click();
await shot(adm, 'web-admin-user', false);
await adm.locator('.drawer').getByRole('button', { name: 'Xoá tài khoản' }).click();
await adm.getByLabel(`Nhập "${throwaway}" để xác nhận`).fill(throwaway);
await adm.locator('.modal').getByRole('button', { name: 'Xoá tài khoản' }).click();
await adm.locator('.drawer').waitFor({ state: 'detached', timeout: 8000 }).catch(() => problems.push('delete user: drawer stayed'));
const stillThere = await adm.evaluate(e => fetch('/api/admin/overview').then(r => r.json()).then(d => d.users.some(x => x.email === e)), throwaway);
if (stillThere) problems.push('delete user: still listed'); else log('throwaway user deleted');
for (const w of [1024, 768, 390, 360]) {
  await adm.setViewportSize({ width: w, height: 900 });
  await visit(adm, 'admin', `admin-${w}`);
  if (w === 390) { await adm.getByRole('tab', { name: /^Người dùng/ }).click(); await shot(adm, 'web-admin-mobile'); }
}
await adm.context().close();

await browser.close();
fs.rmSync(LONG_JAR, { force: true });
if (problems.length) {
  console.log('\nPROBLEMS:\n' + problems.map(p => '  - ' + p).join('\n'));
  process.exit(1);
}
console.log('\nQA passed: no page/console errors, no overflow or clipping at ' + WIDTHS.join('/') + 'px in both themes, stream ≥20 fps, rotation, admin content + user lifecycle.');
