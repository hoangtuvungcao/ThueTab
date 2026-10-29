// End-to-end QA for growth & support features. Usage: npm run build && node qa-features.mjs
// Admin and QA user sessions stay open side by side for flows that cross roles (coupon, ticket, maintenance).
// Everything created is removed again; maintenance is always switched back off.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const BASE = process.env.QA_BASE || 'http://127.0.0.1:8000';
const DOCS = path.resolve('../docs');
const cred = f => { const t = fs.readFileSync(path.resolve('../data', f), 'utf8'); return { email: t.match(/Email: (.+)/)[1].trim(), password: t.match(/Password: (.+)/)[1].trim() }; };
const QA = cred('QA_LOGIN.txt'), ADMIN = cred('LOCAL_LOGIN.txt');
const STAMP = Date.now().toString().slice(-5);
const COUPON = 'QA' + STAMP;
const TAB = 'QA tính năng ' + STAMP;
const FIXTURE = path.resolve('qa-fixtures/hello-midlet.jar');

const browser = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', headless: true, args: ['--no-sandbox'] });
const problems = [];
const log = (...a) => console.log('•', ...a);
const shot = (p, name, full = false) => p.screenshot({ path: `${DOCS}/${name}.png`, fullPage: full });
const expected = url => /\/api\/(me|tabs|slots|jars|wallet|notifications)$|\/frame$|\/stream\?|\/api\/share\//.test(url);

async function page(label, viewport = { width: 1440, height: 900 }) {
  const ctx = await browser.newContext({ viewport });
  const p = await ctx.newPage();
  p.on('pageerror', e => problems.push(`[${label}] pageerror: ${e.message}`));
  p.on('console', m => {
    if (m.type() !== 'error') return;
    if (/Failed to load resource|WebSocket connection/.test(m.text()) && expected(m.location().url || '')) return;
    problems.push(`[${label}] console: ${m.text()} ${m.location().url || ''}`);
  });
  return p;
}
async function login(p, { email, password }) {
  await p.goto(BASE, { waitUntil: 'domcontentloaded' });
  await p.getByRole('button', { name: 'Đăng nhập', exact: true }).first().click();
  await p.locator('[name=email]').fill(email);
  await p.locator('[name=password]').fill(password);
  await p.locator('form button[type=submit]').click();
  await p.locator('.topbar').waitFor({ timeout: 10000 });
  log('logged in as', email);
}
const go = (p, h) => p.evaluate(h => { location.hash = '/' + h; }, h);
const api = (p, path, method = 'GET', body) => p.evaluate(([path, method, body]) => fetch('/api' + path, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }).then(async r => ({ status: r.status, data: await r.json().catch(() => null) })), [path, method, body]);
const adminSection = async (p, name) => { await go(p, 'admin'); await p.getByRole('tab', { name: new RegExp('^' + name) }).click(); await p.waitForTimeout(500); };
async function step(name, fn) {
  try { await fn(); log(name, 'ok'); } catch (e) { problems.push(`${name}: ${e.message.split('\n')[0]}`); }
}

const adm = await page('admin');
await login(adm, ADMIN);
const u = await page('user');
await login(u, QA);

try {
  // ---------- coupon: create (admin) → apply in rent (price drops) → delete ----------
  await step('coupon create', async () => {
    await adminSection(adm, 'Mã khuyến mãi');
    await adm.getByRole('button', { name: 'Tạo mã' }).click();
    await adm.locator('#coupon-form').getByLabel('Mã', { exact: true }).fill(COUPON);
    await adm.locator('#coupon-form').getByRole('radio', { name: /Giảm % khi thuê/ }).click();
    await adm.locator('#coupon-form').getByLabel('Giá trị (%)').fill('50');
    await shot(adm, 'admin-coupon-form');
    await adm.locator('.modal').getByRole('button', { name: 'Tạo mã' }).click();
    await adm.locator('code', { hasText: COUPON }).waitFor({ timeout: 8000 });
    await shot(adm, 'admin-coupons', true);
  });
  // The QA tab is rented with the coupon (no game yet).
  await step('coupon applied in rent', async () => {
    await go(u, 'tabs');
    await u.getByRole('button', { name: /^Thuê tab/ }).first().click();
    await u.getByRole('radio', { name: /^1 ngày/ }).click();
    await u.getByLabel('Tên tab').fill(TAB);
    await u.getByRole('radio', { name: /Chọn game sau/ }).click();
    await u.locator('#cp-rent').fill(COUPON);
    await u.locator('.modal').getByRole('button', { name: 'Áp dụng' }).click();
    await u.locator('.coupon .success-text').waitFor({ timeout: 6000 });
    const btn = await u.locator('.modal-foot button[type=submit]').innerText();
    if (!/750/.test(btn)) throw new Error('discount not reflected: ' + btn);
    if (!(await u.locator('.cost s').count())) throw new Error('original price not struck through');
    await shot(u, 'rent-coupon');
    await u.locator('.modal-foot button[type=submit]').click();
    await u.locator('.tab-card', { hasText: TAB }).waitFor({ timeout: 10000 });
  });
  await step('coupon delete', async () => {
    await adm.getByRole('button', { name: `Xoá ${COUPON}` }).click();
    await adm.locator('.modal').getByRole('button', { name: 'Xoá mã' }).click();
    await adm.locator('code', { hasText: COUPON }).first().waitFor({ state: 'detached', timeout: 8000 }).catch(async () => {
      if ((await api(adm, '/admin/coupons')).data.coupons.some(c => c.code === COUPON)) throw new Error('still listed');
    });
  });

  // ---------- ticket: user creates → admin replies → bell → user closes ----------
  await step('ticket round-trip', async () => {
    await go(u, 'support');
    await u.getByRole('button', { name: 'Tạo yêu cầu' }).first().click();
    await u.getByLabel('Tiêu đề').fill('QA kiểm tra hỗ trợ ' + STAMP);
    await u.getByLabel('Nội dung').fill('Đây là yêu cầu kiểm thử tự động. Vui lòng bỏ qua.');
    await u.locator('.modal').getByRole('button', { name: 'Gửi yêu cầu' }).click();
    await u.locator('.thread h2', { hasText: STAMP }).waitFor({ timeout: 8000 });
    await adminSection(adm, 'Hỗ trợ');
    await adm.locator('tr.clickable', { hasText: STAMP }).click();
    await adm.locator('.reply textarea').fill('Chào bạn, đội hỗ trợ đã nhận được yêu cầu.');
    await adm.locator('.reply').getByRole('button', { name: 'Gửi' }).click();
    await adm.locator('.msg.mine').waitFor({ timeout: 8000 });
    await shot(adm, 'admin-support-thread');
    // Bell on the user side
    await u.waitForFunction(() => !!document.querySelector('.bell-badge'), null, { timeout: 15000 });
    await u.locator('.bell .btn').click();
    await u.locator('.notes .note.unread').first().waitFor();
    await shot(u, 'notifications');
    await u.locator('.notes .note.unread').first().click();
    await u.locator('.msg.staff').waitFor({ timeout: 8000 });
    await u.getByRole('button', { name: 'Đóng', exact: true }).click();
    await u.locator('.thread .badge', { hasText: 'Đã đóng' }).waitFor({ timeout: 8000 });
    await shot(u, 'support-thread');
  });

  // ---------- give the tab a game so frames exist ----------
  const card = u.locator('.tab-card', { hasText: TAB });
  await step('game for tab', async () => {
    await go(u, 'jars');
    if (!(await u.getByText('hello-midlet.jar').count())) {
      await u.locator('.dropzone input[type=file]').setInputFiles(FIXTURE);
      await u.getByText('hello-midlet.jar').first().waitFor({ timeout: 10000 });
    }
    await go(u, 'tabs');
    await card.getByRole('button', { name: 'Chọn game' }).first().click();
    await u.getByRole('radio', { name: /hello-midlet\.jar/ }).first().click();
    await u.getByRole('button', { name: 'Chạy game này' }).click();
    await card.locator('.card-media img.fg').waitFor({ timeout: 45000 });
  });

  // ---------- share link: create → open without login → frames → revoke ----------
  await step('share link', async () => {
    await card.getByRole('button', { name: /Thao tác khác/ }).click();
    await u.getByRole('menuitem', { name: 'Chia sẻ' }).click();
    await u.locator('.share-form').getByRole('radio', { name: 'Chỉ xem' }).click();
    await u.locator('.share-form').getByRole('radio', { name: '1 giờ' }).click();
    await u.getByLabel('Ghi chú link').fill('QA');
    await u.locator('.share-form').getByRole('button', { name: 'Tạo link' }).click();
    const item = u.locator('.share-list li').first();
    await item.waitFor({ timeout: 8000 });
    const url = (await item.locator('.mono').innerText()).trim();
    await shot(u, 'share-dialog');
    const guest = await page('share-guest', { width: 1280, height: 800 });
    await guest.goto(url, { waitUntil: 'domcontentloaded' });
    await guest.waitForFunction(() => { const c = document.querySelector('.share-stage canvas.screen-media:not([hidden])'); return c && c.width > 0; }, null, { timeout: 45000 });
    if (!(await guest.locator('.badge', { hasText: 'Chỉ xem' }).count())) throw new Error('read-only badge missing');
    if (await guest.locator('.share-pad').count()) throw new Error('keypad shown on view-only link');
    await guest.waitForTimeout(1500);
    await shot(guest, 'share-public');
    await item.getByRole('button', { name: 'Thu hồi link' }).click();
    await u.locator('.share-list li').first().waitFor({ state: 'detached', timeout: 8000 }).catch(() => {});
    await guest.reload({ waitUntil: 'domcontentloaded' });
    await guest.locator('.share-gone').waitFor({ timeout: 8000 });
    await shot(guest, 'share-revoked');
    await guest.context().close();
    await u.locator('.modal').getByRole('button', { name: 'Đóng', exact: true }).first().click();
  });

  // ---------- batch group + restart; schedule set + clear ----------
  await step('batch group + restart', async () => {
    await u.getByRole('button', { name: 'Chọn', exact: true }).click();
    await card.locator('.card-check input').check();
    await u.locator('.batch-bar').getByRole('button', { name: 'Gán nhóm' }).click();
    await u.getByLabel('Tên nhóm').fill('Nhóm QA');
    await u.locator('.modal').getByRole('button', { name: 'Lưu' }).click();
    await card.locator('.badge', { hasText: 'Nhóm QA' }).waitFor({ timeout: 8000 });
    await card.locator('.card-check input').check().catch(() => {});
    await u.locator('.batch-bar').getByRole('button', { name: /Khởi động lại/ }).click();
    await u.locator('.toast', { hasText: 'khởi động lại' }).first().waitFor({ timeout: 8000 });
    await shot(u, 'tabs-groups', true);
    await u.locator('.batch-bar').getByRole('button', { name: 'Thoát chế độ chọn' }).click();
  });
  await step('schedule set + clear', async () => {
    await card.getByRole('button', { name: /Thao tác khác/ }).click();
    await u.getByRole('menuitem', { name: /^Nhóm & hẹn giờ/ }).click();
    await u.locator('#schedule .switch-row').click();
    await u.locator('#schedule input[type=time]').fill('04:30');
    await shot(u, 'schedule-dialog');
    await u.locator('.modal').getByRole('button', { name: 'Lưu' }).click();
    await card.locator('.badge', { hasText: '04:30' }).waitFor({ timeout: 8000 });
    await card.getByRole('button', { name: /Thao tác khác/ }).click();
    await u.getByRole('menuitem', { name: /^Nhóm & hẹn giờ/ }).click();
    await u.locator('#schedule .switch-row').click();
    await u.locator('.modal').getByRole('button', { name: 'Lưu' }).click();
    await card.locator('.badge', { hasText: '04:30' }).waitFor({ state: 'detached', timeout: 8000 });
  });

  // ---------- referral, sessions ----------
  await step('referral page', async () => {
    await go(u, 'referral');
    await u.locator('.code-box code').waitFor({ timeout: 8000 });
    await shot(u, 'referral', true);
  });
  await step('sessions', async () => {
    await go(u, 'account');
    await u.locator('.card', { hasText: 'Thiết bị đăng nhập' }).locator('.badge', { hasText: 'Thiết bị này' }).waitFor({ timeout: 8000 });
    await shot(u, 'account-sessions', true);
  });

  // ---------- maintenance on → banner + rent disabled → off ----------
  await step('maintenance', async () => {
    await adminSection(adm, 'Bảo trì');
    await adm.getByRole('button', { name: 'Bật bảo trì' }).click();
    await adm.locator('.modal').getByRole('button', { name: 'Bật bảo trì' }).click();
    await adm.locator('.badge', { hasText: 'Đang bảo trì' }).waitFor({ timeout: 8000 });
    await shot(adm, 'admin-maintenance');
    await u.reload({ waitUntil: 'domcontentloaded' });
    await go(u, 'tabs');
    await u.locator('.maint').waitFor({ timeout: 10000 });
    if (!(await u.getByRole('button', { name: /^Thuê tab/ }).first().isDisabled())) throw new Error('rent not disabled');
    await shot(u, 'maintenance-user');
    await adm.getByRole('button', { name: 'Tắt bảo trì' }).click();
    await adm.locator('.badge', { hasText: 'Hoạt động bình thường' }).waitFor({ timeout: 8000 });
    await u.reload({ waitUntil: 'domcontentloaded' });
    await u.locator('.topbar').waitFor();
    await u.waitForTimeout(1000);
    if (await u.locator('.maint').count()) throw new Error('banner still shown after turning off');
  });

  // ---------- admin screens ----------
  await step('admin screens', async () => {
    for (const [name, file] of [['Thông báo', 'admin-notify'], ['Tăng trưởng', 'admin-growth'], ['Tổng quan', 'admin-dashboard']]) {
      await adminSection(adm, name);
      await shot(adm, file, true);
    }
  });
} finally {
  // Always restore maintenance and remove what we created.
  const m = await api(adm, '/admin/growth');
  if (m.data?.maintenance?.enabled) await api(adm, '/admin/settings/maintenance', 'PUT', { ...m.data.maintenance, enabled: false });
  const cs = await api(adm, '/admin/coupons');
  if (cs.data?.coupons?.some(c => c.code === COUPON)) await api(adm, '/admin/coupons/' + COUPON, 'DELETE');
  const tabs = (await api(u, '/tabs')).data || [];
  for (const t of tabs.filter(t => t.name.startsWith('QA tính năng'))) await api(u, '/tabs/' + t.id, 'PATCH', { desired: 'stopped' });
  for (let i = 0; i < 20; i++) {
    const left = ((await api(u, '/tabs')).data || []).filter(t => t.name.startsWith('QA tính năng'));
    if (!left.length) break;
    for (const t of left.filter(t => ['stopped', 'expired', 'error', 'idle'].includes(t.status))) await api(u, '/tabs/' + t.id, 'DELETE');
    await u.waitForTimeout(2000);
  }
  for (const j of ((await api(u, '/jars')).data || []).filter(j => j.filename === 'hello-midlet.jar')) await api(u, '/jars/' + j.id, 'DELETE');
  log('cleanup done');
}

await browser.close();
if (problems.length) { console.log('\nPROBLEMS:\n' + problems.map(p => '  - ' + p).join('\n')); process.exit(1); }
console.log('\nFeature QA passed: coupon, support + notifications, share link, batch + schedule, referral, sessions, maintenance.');
