// QA for the share-link QR code. Usage: npm run build && node qa-share-qr.mjs
// Registers a throwaway user, credits it via scripts/manage.py, rents a tab, opens the share dialog at 1440 and 390,
// checks the rendered QR encodes exactly the link (re-encoded in Node with the same library), checks the public page,
// then deletes the user (which removes its tab, slot and links).
import { chromium } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import qrcode from 'qrcode-generator';
import path from 'node:path';

const BASE = process.env.QA_BASE || 'http://127.0.0.1:8000';
const ROOT = path.resolve('..');
const DOCS = path.join(ROOT, 'docs');
const EMAIL = `qa-qr-${Date.now()}@thuetab.local`;
const PASSWORD = 'QaQrTam' + Math.random().toString(36).slice(2, 10);
const manage = (...args) => execFileSync(path.join(ROOT, '.venv/bin/python'), ['scripts/manage.py', ...args], { cwd: ROOT, encoding: 'utf8' });

const problems = [];
const log = (...a) => console.log('•', ...a);
// Same path construction as src/components/QrCode.jsx (4-module quiet zone).
function expectedPath(text) {
  const qr = qrcode(0, 'M');
  qr.addData(text);
  qr.make();
  let d = '';
  const n = qr.getModuleCount();
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (qr.isDark(r, c)) d += `M${c + 4},${r + 4}h1v1h-1z`;
  return d;
}

const browser = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', headless: true, args: ['--no-sandbox'] });
let registered = false;
try {
  const boot = await (await browser.newContext()).newPage();
  await boot.goto(BASE, { waitUntil: 'domcontentloaded' });
  const reg = await boot.evaluate(([e, p]) => fetch('/api/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: e, password: p, name: 'QA mã QR' }) }).then(r => r.status), [EMAIL, PASSWORD]);
  if (reg !== 201 && reg !== 200) throw new Error('register ' + reg);
  registered = true;
  log('registered', EMAIL);
  log(manage('credit', '--email', EMAIL, '--amount', '20000', '--reason', 'QA tạm').trim());
  const login = await boot.evaluate(([e, p]) => fetch('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: e, password: p }) }).then(r => r.status), [EMAIL, PASSWORD]);
  if (login !== 200) throw new Error('login ' + login);
  const tab = await boot.evaluate(() => fetch('/api/tabs', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'QA mã QR', plan: 'day' }) }).then(r => r.json()));
  if (!tab.id) throw new Error('rent: ' + JSON.stringify(tab));
  log('rented tab', tab.id);
  const state = await boot.context().storageState();
  await boot.context().close();

  let shareUrl = '';
  for (const [w, h] of [[1440, 900], [390, 844]]) {
    const p = await (await browser.newContext({ viewport: { width: w, height: h }, storageState: state })).newPage();
    p.on('pageerror', e => problems.push(`[${w}] pageerror ${e.message}`));
    await p.goto(BASE + '/#/tabs', { waitUntil: 'domcontentloaded' });
    const card = p.locator('.tab-card', { hasText: 'QA mã QR' });
    await card.waitFor({ timeout: 15000 });
    await card.getByRole('button', { name: /Thao tác khác/ }).click();
    await p.getByRole('menuitem', { name: 'Chia sẻ' }).click();
    if (!shareUrl) await p.locator('.share-form').getByRole('button', { name: 'Tạo link' }).click();
    const item = p.locator('.share-list li').first();
    await item.waitFor({ timeout: 8000 });
    shareUrl = (await item.locator('.mono').innerText()).trim();
    const svg = p.locator('.share-qr .qr-frame svg');
    await svg.waitFor({ timeout: 8000 });
    const d = await svg.locator('path').getAttribute('d');
    if (d !== expectedPath(shareUrl)) problems.push(`[${w}] QR does not encode the link`);
    else log(`[${w}] QR encodes ${shareUrl}`);
    const box = await svg.boundingBox();
    if (Math.abs(box.width - 160) > 1) problems.push(`[${w}] QR is ${box.width}px, expected 160`);
    if (!(await p.getByText('Mở trên điện thoại').count())) problems.push(`[${w}] hint missing`);
    if (!(await p.getByRole('button', { name: 'Tải ảnh PNG' }).isEnabled())) problems.push(`[${w}] PNG button disabled`);
    await p.waitForTimeout(400);
    await p.screenshot({ path: `${DOCS}/share-qr-${w}.png` });
    // PNG download produces a file
    const dl = p.waitForEvent('download');
    await p.getByRole('button', { name: 'Tải ảnh PNG' }).evaluate(b => b.click());
    const file = await dl;
    log(`[${w}] PNG download`, file.suggestedFilename());
    await p.context().close();
  }

  // Public share page: copy link + QR toggle
  const g = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
  await g.goto(shareUrl, { waitUntil: 'domcontentloaded' });
  await g.getByRole('button', { name: 'Mã QR' }).click();
  const psvg = g.locator('.share-qr .qr-frame svg');
  await psvg.waitFor({ timeout: 8000 });
  const pd = await psvg.locator('path').getAttribute('d');
  const pageUrl = await g.evaluate(() => location.href);
  if (pd !== expectedPath(pageUrl)) problems.push('public page QR does not encode its URL');
  else log('public page QR ok');
  await g.screenshot({ path: `${DOCS}/share-qr-public.png` });
  await g.context().close();
} catch (e) {
  problems.push(e.message.split('\n')[0]);
} finally {
  if (registered) { try { log(manage('delete-user', '--email', EMAIL).trim()); } catch (e) { problems.push('delete-user: ' + e.message.split('\n')[0]); } }
  await browser.close();
}
if (problems.length) { console.log('\nPROBLEMS:\n' + problems.map(p => '  - ' + p).join('\n')); process.exit(1); }
console.log('\nShare QR QA passed.');
