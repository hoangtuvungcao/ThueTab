// Layout audit at phone and desktop sizes. Usage: npm run build && node qa-layout.mjs
// Phones (touch emulation) and desktops: open the Tabs page, press "Chơi", then assert every visible control of the
// viewer is fully inside the viewport, not covered (elementFromPoint), and that nothing scrolls. On desktop sizes it
// also opens every dialog (rent, change game, screen, JAR delete confirm) and the admin user drawer + its confirms,
// asserting the fixed parts (header, footer, actions) are on screen; scrollable dialog bodies may scroll internally.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const BASE = process.env.QA_BASE || 'http://127.0.0.1:8000';
const DOCS = path.resolve('../docs');
const cred = f => { const t = fs.readFileSync(path.resolve('../data', f), 'utf8'); return { email: t.match(/Email: (.+)/)[1].trim(), password: t.match(/Password: (.+)/)[1].trim() }; };
const QA = cred('QA_LOGIN.txt'), ADMIN = cred('LOCAL_LOGIN.txt');
const PHONES = [[360, 740], [390, 844], [412, 915], [844, 390], [915, 412], [740, 360]];
const DESKTOPS = [[1280, 720], [1366, 768], [1280, 800], [1440, 900], [1920, 1080], [1024, 768]];

const browser = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', headless: true, args: ['--no-sandbox'] });
const problems = [];
const log = (...a) => console.log('•', ...a);

async function session(c) {
  const ctx = await browser.newContext();
  const p = await ctx.newPage();
  await p.goto(BASE, { waitUntil: 'domcontentloaded' });
  const r = await p.evaluate(c => fetch('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(c) }).then(x => x.status), c);
  if (r !== 200) throw new Error('login failed ' + r);
  const st = await ctx.storageState();
  await ctx.close();
  return st;
}
const userState = await session(QA);
const adminState = await session(ADMIN);

// Fixture: a running J2ME tab owned by this script (free slot if any), removed at the end.
const fixtureCtx = await browser.newContext({ storageState: userState });
const fx = await fixtureCtx.newPage();
await fx.goto(BASE, { waitUntil: 'domcontentloaded' });
const call = (p, m = 'GET', b) => fx.evaluate(([p, m, b]) => fetch('/api' + p, { method: m, headers: { 'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined }).then(r => r.json().catch(() => null)), [p, m, b]);
const jarBytes = [...fs.readFileSync(path.resolve('qa-fixtures/hello-midlet.jar'))];
const jar = (await fx.evaluate(bytes => fetch('/api/jars/upload', { method: 'POST', headers: { 'X-Filename': 'qa-layout.jar' }, body: new Uint8Array(bytes) }).then(r => r.json()), jarBytes)).jar;
const slot = ((await call('/slots')) || []).find(s => !s.tab_id && s.expires > Date.now() / 1000);
const fixtureTab = await call('/tabs', 'POST', { name: 'QA bố cục', plan: 'day', slot_id: slot?.id, game: 'custom-jar', custom_jar_id: jar.id });
if (!fixtureTab?.id) throw new Error('could not create fixture tab: ' + JSON.stringify(fixtureTab));
log('fixture tab', fixtureTab.id, slot ? '(free slot)' : '(paid 1 day)');
async function removeFixture() {
  // Removes this run's fixture and any left by an interrupted run.
  const mine = async () => ((await call('/tabs')) || []).filter(x => x.name === 'QA bố cục');
  for (const t of await mine()) await call('/tabs/' + t.id, 'PATCH', { desired: 'stopped' });
  for (let i = 0; i < 25; i++) {
    const left = await mine();
    if (!left.length) break;
    for (const t of left.filter(t => ['stopped', 'expired', 'error', 'idle'].includes(t.status))) await call('/tabs/' + t.id, 'DELETE');
    await fx.waitForTimeout(2000);
  }
  const used = new Set(((await call('/tabs')) || []).map(t => t.custom_jar_id));
  for (const j of ((await call('/jars')) || []).filter(j => j.filename === 'qa-layout.jar' && !used.has(j.id))) await call('/jars/' + j.id, 'DELETE');
  await fixtureCtx.close();
}

// Every visible control under `root` must be inside the viewport and hit-testable; controls inside internally
// scrolling bodies (.modal-body, .drawer-body) are skipped. With `viewer`, the page must not scroll either.
async function check(page, label, root, viewer = false) {
  const bad = await page.evaluate(([root, viewer]) => {
    const out = [];
    const W = innerWidth, H = innerHeight;
    const scope = document.querySelector(root);
    if (!scope) return [`${root} not found`];
    for (const el of scope.querySelectorAll('button, select, input:not([type=checkbox]):not([type=range]):not([type=file]), a.btn')) {
      if (el.closest('.modal-body, .drawer-body, .notes-list, [hidden]')) continue;
      const st = getComputedStyle(el);
      if (st.display === 'none' || st.visibility === 'hidden') continue;
      const b = el.getBoundingClientRect();
      if (!b.width || !b.height) continue;
      const name = el.getAttribute('aria-label') || el.textContent.trim().slice(0, 24) || el.className;
      if (b.left < -0.5 || b.top < -0.5 || b.right > W + 0.5 || b.bottom > H + 0.5) { out.push(`${name}: outside viewport (${Math.round(b.left)},${Math.round(b.top)}→${Math.round(b.right)},${Math.round(b.bottom)})`); continue; }
      const hit = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
      if (!hit || !(hit === el || el.contains(hit))) out.push(`${name}: covered by ${hit?.className?.baseVal ?? hit?.className ?? hit?.tagName}`);
    }
    if (viewer) {
      const se = document.scrollingElement;
      const locked = getComputedStyle(document.documentElement).overflow === 'hidden' && getComputedStyle(document.body).overflow === 'hidden';
      if (!locked && (se.scrollHeight > innerHeight + 1 || se.scrollWidth > innerWidth + 1)) out.push(`document scrolls (${se.scrollWidth}×${se.scrollHeight})`);
      const v = document.querySelector('.viewer');
      if (v && v.scrollHeight > v.clientHeight + 1) out.push(`viewer scrolls (${v.scrollHeight} > ${v.clientHeight})`);
      for (const s of v.querySelectorAll('.v-pad, .v-stage')) if (s.scrollHeight > s.clientHeight + 1) out.push(`${s.className} overflows (${s.scrollHeight} > ${s.clientHeight})`);
    }
    return out;
  }, [root, viewer]);
  bad.forEach(b => problems.push(`[${label}] ${b}`));
}

async function openTabs(page) {
  await page.goto(BASE + '/#/tabs', { waitUntil: 'domcontentloaded' });
  await page.locator('.tab-card').first().waitFor({ timeout: 15000 });
}
async function openViewer(page, label) {
  const play = page.locator('.tab-card', { hasText: 'QA bố cục' }).getByRole('button', { name: /^Chơi$/ }).first();
  await play.evaluate(el => el.scrollIntoView({ block: 'center' }));
  await page.waitForTimeout(300);
  const covered = await play.evaluate(el => { const b = el.getBoundingClientRect(); const hit = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2); return !(hit === el || el.contains(hit)); });
  if (covered) problems.push(`[${label}] tabs page: "Chơi" is covered`);
  await play.click({ timeout: 8000 });
  await page.locator('.viewer').waitFor();
  await page.waitForFunction(() => !!document.querySelector('.viewer .screen.fit[style*="width"]'), null, { timeout: 15000 }).catch(() => problems.push(`[${label}] screen never sized`));
  await page.waitForTimeout(2500);
  await check(page, label, '.viewer', true);
  const sb = await page.locator('.viewer .screen.fit').boundingBox();
  log(`${label}: screen ${Math.round(sb.width)}×${Math.round(sb.height)} at ${Math.round(sb.x)},${Math.round(sb.y)}`);
}

// Touch mode: hide the virtual keys, the game screen must grow and every remaining control stay on screen.
async function touchMode(page, label) {
  const before = await page.locator('.viewer .screen.fit').boundingBox();
  await page.getByRole('button', { name: 'Ẩn phím ảo (chơi bằng chạm)' }).first().click();
  await page.waitForTimeout(400);
  if (await page.locator('.viewer .v-pad, .viewer .v-overlay.left, .viewer .v-overlay.right').count()) problems.push(`[${label} touch] virtual keys still shown`);
  await check(page, label + ' touch', '.viewer', true);
  const after = await page.locator('.viewer .screen.fit').boundingBox();
  if (after.width * after.height < before.width * before.height - 1) problems.push(`[${label} touch] screen shrank`);
  log(`${label} touch: screen ${Math.round(after.width)}×${Math.round(after.height)}`);
  await page.screenshot({ path: `${DOCS}/viewer-${label}-touch.png` });
  await page.getByRole('button', { name: 'Hiện phím ảo' }).first().click();
}

// ---------- phones (touch) ----------
for (const [w, h] of PHONES) {
  const label = `${w}x${h}`;
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: true, hasTouch: true, deviceScaleFactor: 2, storageState: userState });
  const page = await ctx.newPage();
  page.on('pageerror', e => problems.push(`[${label}] pageerror ${e.message}`));
  await openTabs(page);
  if (h > w) {
    await page.locator('.bell .btn').click();
    await page.locator('.notes').waitFor();
    await page.waitForTimeout(350); // sheet/popover open animation
    await check(page, label + ' bell', '.notes');
    await page.keyboard.press('Escape');
  }
  await openViewer(page, label);
  await page.screenshot({ path: `${DOCS}/viewer-${label}.png` });
  const t123 = page.locator('.viewer .pad-123, .viewer .v-123').first();
  if (await t123.isVisible()) {
    await t123.click();
    await page.waitForTimeout(250);
    await check(page, label + '+123', '.viewer', true);
    await page.screenshot({ path: `${DOCS}/viewer-${label}-123.png` });
    await t123.click();
  }
  await touchMode(page, label);
  await ctx.close();
}

// ---------- desktops: viewer + every dialog ----------
for (const [w, h] of DESKTOPS) {
  const label = `${w}x${h}`;
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, storageState: userState });
  const page = await ctx.newPage();
  page.on('pageerror', e => problems.push(`[${label}] pageerror ${e.message}`));
  await openTabs(page);
  // Rent dialog (long: plans + name + game picker + screen picker) — footer must stay visible.
  await page.getByRole('button', { name: /^Thuê tab/ }).first().click();
  await page.locator('.modal').waitFor();
  await check(page, label + ' rent', '.modal');
  if (w === 1280 && h === 720) await page.screenshot({ path: `${DOCS}/dialog-rent-${label}.png` });
  await page.locator('.modal').getByRole('button', { name: 'Hủy' }).click();
  // Card menu → change game, screen picker.
  for (const item of [/^Đổi game$|^Chọn game$/, /^Màn hình/, /^Chia sẻ$/, /^Nhóm & hẹn giờ/]) {
    const card = page.locator('.tab-card', { hasText: 'QA bố cục' }).first();
    await card.getByRole('button', { name: /Thao tác khác/ }).click();
    const mi = page.getByRole('menuitem', { name: item });
    if (!(await mi.count())) { await page.keyboard.press('Escape'); continue; }
    await mi.first().click();
    await page.locator('.modal').waitFor();
    await page.waitForTimeout(400);
    await check(page, `${label} ${item}`, '.modal');
    if (w === 1280 && h === 720) await page.screenshot({ path: `${DOCS}/dialog-${String(item).replace(/[^a-z]/gi, '').slice(0, 12)}-${label}.png` });
    await page.keyboard.press('Escape');
    await page.locator('.modal').waitFor({ state: 'detached' });
  }
  // Notification bell dropdown
  await page.locator('.bell .btn').click();
  await page.locator('.notes').waitFor();
  await page.waitForTimeout(350);
  await check(page, label + ' bell', '.notes');
  await page.keyboard.press('Escape');
  await openViewer(page, label);
  await page.screenshot({ path: `${DOCS}/viewer-${label}.png` });
  await touchMode(page, label);
  await page.locator('.v-head').getByRole('button', { name: 'Đóng', exact: true }).click();
  // JAR delete confirm
  await page.evaluate(() => { location.hash = '/jars'; });
  const delBtn = page.getByRole('button', { name: /^Xóa / }).first();
  if (await delBtn.count()) {
    await delBtn.click();
    await page.locator('.modal').waitFor();
    await check(page, label + ' jar-confirm', '.modal');
    await page.locator('.modal').getByRole('button', { name: 'Hủy' }).click();
  }
  await ctx.close();
}

// ---------- admin drawer + confirms (desktop + phone) ----------
for (const [w, h] of [[1280, 720], [1024, 768], [390, 844]]) {
  const label = `admin ${w}x${h}`;
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, storageState: adminState, ...(w < 500 ? { isMobile: true, hasTouch: true } : {}) });
  const page = await ctx.newPage();
  page.on('pageerror', e => problems.push(`[${label}] pageerror ${e.message}`));
  await page.goto(BASE + '/#/admin', { waitUntil: 'domcontentloaded' });
  await page.getByRole('tab', { name: /^Người dùng/ }).click();
  await page.locator('tr.clickable').first().click();
  await page.locator('.drawer').waitFor();
  await page.waitForTimeout(800);
  await check(page, label + ' drawer', '.drawer');
  await page.screenshot({ path: `${DOCS}/admin-drawer-${w}x${h}.png` });
  for (const btn of ['Đặt lại mật khẩu', 'Đăng xuất mọi thiết bị']) {
    await page.locator('.drawer').getByRole('button', { name: btn }).click();
    await page.locator('.modal').waitFor();
    await page.waitForTimeout(350); // bottom-sheet slide-in on phones
    await check(page, `${label} ${btn}`, '.modal');
    await page.locator('.modal').getByRole('button', { name: 'Hủy' }).click();
  }
  await ctx.close();
}

await removeFixture();
await browser.close();
if (problems.length) { console.log('\nPROBLEMS:\n' + problems.map(p => '  - ' + p).join('\n')); process.exit(1); }
console.log('\nLayout OK at phones ' + PHONES.map(s => s.join('×')).join(', ') + ' and desktops ' + DESKTOPS.map(s => s.join('×')).join(', '));
