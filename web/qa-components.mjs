// Component QA (tokens.components): every dialog, confirm, toast stack, notification popover, menu and banner at
// 1440 / 1024 / 390 / 360 in dark and light. Asserts every visible button matches its size token (±1px) and that
// dialogs are centred in the viewport on desktop. Usage: npm run build && node qa-components.mjs
// Creates a fixture tab + jar, seeds 3 notifications, toggles banners — everything is restored at the end.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const BASE = process.env.QA_BASE || 'http://127.0.0.1:8000';
const OUT = path.resolve('../docs/components');
fs.mkdirSync(OUT, { recursive: true });
const tokens = JSON.parse(fs.readFileSync(path.resolve('../design/tokens.json'), 'utf8')).components;
const cred = f => { const t = fs.readFileSync(path.resolve('../data', f), 'utf8'); return { email: t.match(/Email: (.+)/)[1].trim(), password: t.match(/Password: (.+)/)[1].trim() }; };
const QA = cred('QA_LOGIN.txt'), ADMIN = cred('LOCAL_LOGIN.txt');
const WIDTHS = [[1440, 900], [1024, 768], [390, 844], [360, 740]];
const THEMES = ['dark', 'light'];
const FIXTURE_NAME = 'QA thành phần';

const browser = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', headless: true, args: ['--no-sandbox'] });
const problems = [];
const log = (...a) => console.log('•', ...a);
problems.push = (...items) => { items.forEach(i => console.log('  ✗', i)); return Array.prototype.push.apply(problems, items); };

async function session(c) {
  const ctx = await browser.newContext();
  const p = await ctx.newPage();
  await p.goto(BASE, { waitUntil: 'domcontentloaded' });
  const r = await p.evaluate(c => fetch('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(c) }).then(x => x.status), c);
  if (r !== 200) throw new Error('login failed ' + r + ' for ' + c.email);
  return p;
}
const call = (p, path, method = 'GET', body) => p.evaluate(([path, method, body]) => fetch('/api' + path, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }).then(r => r.json().catch(() => null)), [path, method, body]);

const user = await session(QA);
const admin = await session(ADMIN);
const userState = await user.context().storageState();
const me = await call(user, '/me');
const adminMe = await call(admin, '/me');
const restore = { userTheme: me.prefs.theme, site: (await call(admin, '/admin/settings')).site, maint: (await call(admin, '/admin/growth')).maintenance };

// Remove fixtures stranded by an interrupted run.
async function removeFixtures() {
  for (const t of ((await call(user, '/tabs')) || []).filter(t => t.name === FIXTURE_NAME)) await call(user, '/tabs/' + t.id, 'PATCH', { desired: 'stopped' });
  for (let i = 0; i < 25; i++) {
    const left = ((await call(user, '/tabs')) || []).filter(t => t.name === FIXTURE_NAME);
    if (!left.length) break;
    for (const t of left.filter(t => ['stopped', 'expired', 'error', 'idle'].includes(t.status))) await call(user, '/tabs/' + t.id, 'DELETE');
    await user.waitForTimeout(2000);
  }
  const used = new Set(((await call(user, '/tabs')) || []).map(t => t.custom_jar_id));
  for (const j of ((await call(user, '/jars')) || []).filter(j => j.filename === 'qa-components.jar' && !used.has(j.id))) await call(user, '/jars/' + j.id, 'DELETE');
}
await removeFixtures();
// Fixture tab with a game (free slot if any) so every tab dialog is reachable.
const bytes = [...fs.readFileSync(path.resolve('qa-fixtures/hello-midlet.jar'))];
const jar = (await user.evaluate(b => fetch('/api/jars/upload', { method: 'POST', headers: { 'X-Filename': 'qa-components.jar' }, body: new Uint8Array(b) }).then(r => r.json()), bytes)).jar;
const slot = ((await call(user, '/slots')) || []).find(s => !s.tab_id && s.expires > Date.now() / 1000);
const tab = await call(user, '/tabs', 'POST', { name: FIXTURE_NAME, plan: 'day', slot_id: slot?.id, game: 'custom-jar', custom_jar_id: jar.id });
if (!tab?.id) throw new Error('fixture tab: ' + JSON.stringify(tab));
// Seed three notifications for the QA user.
for (const [t, b] of [['Nạp tiền thành công', 'Ví của bạn vừa được cộng 50.000đ.'], ['Tab sắp hết hạn', 'Tab "QA thành phần" còn dưới 24 giờ. Gia hạn để không bị gián đoạn.'], ['Hỗ trợ đã trả lời', 'Đội ngũ ThuêTab đã phản hồi yêu cầu của bạn.']])
  await call(admin, '/admin/notifications', 'POST', { title: t, body: b, link: '/wallet', user_id: me.id });
log('fixtures ready');

const SIZE = { sm: tokens.button.sm.height, md: tokens.button.md.height, lg: tokens.button.lg.height };
async function assertLayout(page, label, desktop) {
  const bad = await page.evaluate(([SIZE, desktop]) => {
    const out = [];
    for (const b of document.querySelectorAll('.btn')) {
      const st = getComputedStyle(b);
      if (st.display === 'none' || st.visibility === 'hidden' || !b.offsetParent) continue;
      const r = b.getBoundingClientRect();
      if (!r.height) continue;
      const want = b.classList.contains('btn-sm') ? SIZE.sm : b.classList.contains('btn-lg') ? SIZE.lg : SIZE.md;
      if (Math.abs(r.height - want) > 1) out.push(`button "${(b.getAttribute('aria-label') || b.textContent).trim().slice(0, 24)}" is ${r.height.toFixed(1)}px, token ${want}px`);
      if (b.scrollWidth > b.clientWidth + 1) out.push(`button "${b.textContent.trim().slice(0, 24)}" label clipped`);
    }
    const m = document.querySelector('.modal');
    if (m && desktop) {
      const r = m.getBoundingClientRect();
      const lr = Math.abs(r.left - (innerWidth - r.right)), tb = Math.abs(r.top - (innerHeight - r.bottom));
      if (lr > 1) out.push(`dialog not centred horizontally (Δ${lr.toFixed(1)}px)`);
      if (tb > 1) out.push(`dialog not centred vertically (Δ${tb.toFixed(1)}px)`);
    }
    return out;
  }, [SIZE, desktop]);
  bad.forEach(b => problems.push(`[${label}] ${b}`));
}

for (const theme of THEMES) {
  await call(user, '/me/prefs', 'PATCH', { theme });
  for (const [w, h] of WIDTHS) {
    const label = `${theme}-${w}`;
    const desktop = w >= 1024;
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, storageState: userState });
    const p = await ctx.newPage();
    p.on('pageerror', e => problems.push(`[${label}] pageerror ${e.message}`));
    const shot = name => p.screenshot({ path: `${OUT}/${name}-${label}.png` });
    await p.goto(BASE + '/#/tabs', { waitUntil: 'domcontentloaded' });
    const card = p.locator('.tab-card', { hasText: FIXTURE_NAME }).first();
    await card.waitFor({ timeout: 15000 });
    await card.evaluate(el => el.scrollIntoView({ block: 'center' }));
    await p.waitForTimeout(500);
    await assertLayout(p, label + ' tabs', desktop);

    // Card menu
    await card.getByRole('button', { name: /Thao tác khác/ }).click();
    await p.locator('.menu-list[role=menu]').waitFor();
    await p.waitForTimeout(300); // let the open animation finish
    await shot('menu');
    await p.keyboard.press('Escape');

    // Dialogs from the card menu and the page header
    const dialogs = [
      ['rent', async () => p.getByRole('button', { name: /^Thuê tab/ }).first().click()],
      ['rename', async () => { await card.getByRole('button', { name: /Thao tác khác/ }).click(); await p.getByRole('menuitem', { name: 'Đổi tên', exact: true }).click(); }],
      ['renew', async () => { await card.getByRole('button', { name: /Thao tác khác/ }).click(); await p.getByRole('menuitem', { name: 'Gia hạn', exact: true }).click(); }],
      ['game', async () => { await card.getByRole('button', { name: /Thao tác khác/ }).click(); await p.getByRole('menuitem', { name: 'Đổi game', exact: true }).click(); }],
      ['screen', async () => { await card.getByRole('button', { name: /Thao tác khác/ }).click(); await p.getByRole('menuitem', { name: /^Màn hình/ }).click(); }],
      ['schedule', async () => { await card.getByRole('button', { name: /Thao tác khác/ }).click(); await p.getByRole('menuitem', { name: /^Nhóm & hẹn giờ/ }).click(); }],
      ['logs', async () => { await card.getByRole('button', { name: /Thao tác khác/ }).click(); await p.getByRole('menuitem', { name: 'Xem nhật ký' }).click(); }],
      ['slots', async () => { await p.getByRole('button', { name: 'Thao tác khác', exact: true }).click(); await p.getByRole('menuitem', { name: 'Mua slot trống' }).click(); }]
    ];
    for (const [name, openIt] of dialogs) {
      try {
        await openIt();
        await p.locator('.modal').waitFor({ timeout: 5000 });
        await p.waitForTimeout(350);
        await assertLayout(p, `${label} ${name}`, desktop);
        await shot('dialog-' + name);
        await p.keyboard.press('Escape');
        await p.locator('.modal').waitFor({ state: 'detached', timeout: 5000 });
      } catch (e) { problems.push(`[${label}] ${name}: ${e.message.split('\n')[0]}`); await p.keyboard.press('Escape').catch(() => {}); }
    }

    // Share dialog + toast stack (3 links → 3 toasts), then revoke them
    try {
      await card.getByRole('button', { name: /Thao tác khác/ }).click();
      await p.getByRole('menuitem', { name: 'Chia sẻ' }).click();
      await p.locator('.share-form').waitFor();
      // Toasts sit top-centre on phones and may cover the button; click it directly.
      for (let i = 0; i < 3; i++) { await p.locator('.share-form').getByRole('button', { name: 'Tạo link' }).evaluate(b => b.click()); await p.waitForTimeout(450); }
      await p.locator('.toast').nth(2).waitFor({ timeout: 5000 });
      if ((await p.locator('.toast').count()) > tokens.toast.max_visible) problems.push(`[${label}] more than ${tokens.toast.max_visible} toasts`);
      await p.waitForTimeout(250);
      await assertLayout(p, `${label} share`, desktop);
      await shot('dialog-share-toasts');
      for (const s of (await call(p, `/tabs/${tab.id}/shares`)) || []) await call(p, `/tabs/${tab.id}/shares/${s.token}`, 'DELETE');
      await p.keyboard.press('Escape');
    } catch (e) { problems.push(`[${label}] share/toasts: ${e.message.split('\n')[0]}`); await p.keyboard.press('Escape').catch(() => {}); }

    // Notification popover
    try {
      await p.locator('.bell .btn').click();
      await p.locator('.notes .note').first().waitFor({ timeout: 6000 });
      await p.waitForTimeout(250);
      await assertLayout(p, `${label} notifications`, false);
      const pop = await p.locator('.menu-list.notes').boundingBox();
      if (w > 640 && Math.abs(pop.width - tokens.popover.notifications.width) > 1) problems.push(`[${label}] popover width ${pop.width}`);
      await shot('notifications');
      await p.keyboard.press('Escape');
      if (w <= 640) await p.locator('.notes-x').click().catch(() => {});
    } catch (e) { problems.push(`[${label}] notifications: ${e.message.split('\n')[0]}`); await p.keyboard.press('Escape').catch(() => {}); }

    // Confirms: JAR delete (Jars page) and logout-all (Account)
    for (const [route, btn, name] of [['jars', /^Xóa qa-components/, 'confirm-jar'], ['account', /^Đăng xuất mọi thiết bị/, 'confirm-logout']]) {
      try {
        await p.evaluate(r => { location.hash = '/' + r; }, route);
        await p.locator('.page-head h1').waitFor();
        await p.getByRole('button', { name: btn }).first().click();
        await p.locator('.modal.confirm').waitFor({ timeout: 5000 });
        await p.waitForTimeout(300);
        await assertLayout(p, `${label} ${name}`, desktop);
        await shot(name);
        await p.locator('.modal.confirm').getByRole('button', { name: 'Hủy' }).click();
      } catch (e) { problems.push(`[${label}] ${name}: ${e.message.split('\n')[0]}`); }
    }
    // Support: new ticket dialog
    try {
      await p.evaluate(() => { location.hash = '/support'; });
      await p.getByRole('button', { name: 'Tạo yêu cầu' }).first().click();
      await p.locator('.modal').waitFor();
      await p.waitForTimeout(300);
      await assertLayout(p, `${label} ticket`, desktop);
      await shot('dialog-ticket');
      await p.keyboard.press('Escape');
    } catch (e) { problems.push(`[${label}] ticket: ${e.message.split('\n')[0]}`); }
    await ctx.close();
    log(label, 'done');
  }
}

// Banners (announcement + maintenance) at every size/theme, then restore.
try {
  await call(admin, '/admin/settings/site', 'PUT', { ...restore.site, announcement: 'Khuyến mãi tháng 11: giảm 20% gói 30 ngày khi nhập mã THANG11.' });
  await call(admin, '/admin/settings/maintenance', 'PUT', { ...restore.maint, enabled: true, message: 'Bảo trì định kỳ từ 2:00 đến 3:00, tab đang chạy không bị ảnh hưởng.' });
  for (const theme of THEMES) {
    await call(user, '/me/prefs', 'PATCH', { theme });
    for (const [w, h] of WIDTHS) {
      const ctx = await browser.newContext({ viewport: { width: w, height: h }, storageState: userState });
      const p = await ctx.newPage();
      await p.goto(BASE + '/#/tabs', { waitUntil: 'domcontentloaded' });
      await p.locator('.maint').waitFor({ timeout: 10000 });
      await p.locator('.announce').waitFor({ timeout: 10000 });
      await p.waitForTimeout(400);
      await p.screenshot({ path: `${OUT}/banners-${theme}-${w}.png` });
      await ctx.close();
    }
  }
  log('banners done');
} catch (e) { problems.push('banners: ' + e.message.split('\n')[0]); }
finally {
  await call(admin, '/admin/settings/site', 'PUT', restore.site);
  await call(admin, '/admin/settings/maintenance', 'PUT', restore.maint);
  await call(user, '/me/prefs', 'PATCH', { theme: restore.userTheme });
  await call(user, '/notifications/read', 'POST', { all: true });
  await removeFixtures();
  log('restored settings, removed fixtures');
}

await browser.close();
if (problems.length) { console.log('\nPROBLEMS:\n' + problems.map(p => '  - ' + p).join('\n')); process.exit(1); }
console.log('\nComponent QA passed at ' + WIDTHS.map(w => w[0]).join('/') + ' in dark and light.');
