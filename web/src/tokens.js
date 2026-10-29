// Shared design tokens (design/tokens.json) — the same file drives the Godot client.
import tokens from '../../design/tokens.json';

export default tokens;
export const STATUS = tokens.status;
export const JAR_STATUS = tokens.jar_status;
export const NAV = tokens.nav;
export const POLL = tokens.poll_seconds;
export const BRAND = tokens.brand;
export const ORDER_STATUS = tokens.order_status;
export const STREAM = tokens.stream || { fps_choices: [30], default_fps: 30 };
// Web-only additions until tokens.user_menu lists them (support, referral).
const EXTRA_MENU = [{ id: 'support', label: 'Hỗ trợ', icon: 'message-circle' }, { id: 'referral', label: 'Giới thiệu bạn bè', icon: 'gift' }];
export const USER_MENU = [...(tokens.user_menu || []), ...EXTRA_MENU.filter(e => !(tokens.user_menu || []).some(m => m.id === e.id))];
export const ACCENTS = tokens.accents || {};
export const COMPONENTS = tokens.components || {};
export const navLabel = id => NAV.find(n => n.id === id)?.label || '';

import chakra600 from '../../design/fonts/ChakraPetch-SemiBold.ttf';
import chakra700 from '../../design/fonts/ChakraPetch-Bold.ttf';
import vn400 from '../../design/fonts/BeVietnamPro-Regular.ttf';
import vn500 from '../../design/fonts/BeVietnamPro-Medium.ttf';
import vn600 from '../../design/fonts/BeVietnamPro-SemiBold.ttf';

const kebab = k => k.replace(/_/g, '-');
const vars = (obj, prefix = '', unit = '') =>
  Object.entries(obj).map(([k, v]) => `--${prefix}${kebab(k)}:${v}${unit};`).join('');
const face = (family, weight, url) =>
  `@font-face{font-family:'${family}';font-weight:${weight};font-style:normal;font-display:swap;src:url(${url}) format('truetype')}`;

// tokens.components → --c-<path> custom properties, e.g. button.md.height → --c-button-md-height: 40px.
// Font sizes become rem (so the font_scale preference applies); free-text rules/notes are skipped.
function componentVars(c) {
  if (!c) return '';
  const out = [];
  const walk = (o, path) => {
    for (const [k, v] of Object.entries(o)) {
      const name = [...path, k].join('-').replace(/_/g, '-');
      if (v && typeof v === 'object') walk(v, [...path, k]);
      else if (typeof v === 'number') out.push(`--c-${name}:${/font/.test(k) ? v / 16 + 'rem' : /duration|_ms/.test(k) ? v + 'ms' : v + 'px'};`);
    }
  };
  walk(c, []);
  return `:root{${out.join('')}}`;
}

// Writes every token as a CSS custom property so style.css never hard-codes a color, radius, font or effect.
export function applyTokens() {
  const { color, radius, space, font, effects = {} } = tokens;
  const [g1, g2] = effects.gradient || [color.dark.accent, color.dark.accent_2 || color.dark.accent];
  const fx = `--grad:linear-gradient(135deg,${g1},${g2});--glow-alpha:${Math.round((effects.glow_alpha ?? 0.35) * 100)}%;` +
    `--glass-alpha:${Math.round((effects.glass_alpha ?? 1) * 100)}%;--grid-alpha:${effects.grid_pattern ? '35%' : '0%'};`;
  // Font sizes in rem so the user's font_scale preference (root font-size %) scales all text.
  const rem = Object.fromEntries(Object.entries(font.size).map(([k, v]) => [k, v / 16]));
  const compact = Object.fromEntries(Object.entries(space).map(([k, v]) => [k, Math.max(2, Math.round(v * 0.75))]));
  const base = vars(radius, 'r-', 'px') + vars(space, 's-', 'px') + vars(rem, 'fs-', 'rem') +
    `--font:${font.family};--font-display:${font.display_family || font.family};--mono:${font.mono};` + fx;
  const css = componentVars(tokens.components) + face(font.display || 'Chakra Petch', 600, chakra600) + face(font.display || 'Chakra Petch', 700, chakra700) +
    face(font.body || 'Be Vietnam Pro', 400, vn400) + face(font.body || 'Be Vietnam Pro', 500, vn500) + face(font.body || 'Be Vietnam Pro', 600, vn600) +
    `:root{${base}}:root[data-density=compact]{${vars(compact, 's-', 'px')}}` +
    `:root,:root[data-theme=dark]{${vars(color.dark)}color-scheme:dark}` +
    `:root[data-theme=light]{${vars(color.light)}color-scheme:light}`;
  let el = document.getElementById('tt-tokens');
  if (!el) {
    el = document.createElement('style');
    el.id = 'tt-tokens';
    document.head.prepend(el);
  }
  el.textContent = css;
}

// Theme for guests persists per browser; signed-in users use prefs.theme (synced with the app).
// Storage may be unavailable (private mode), so every access is guarded.
export function loadTheme() {
  try {
    const t = localStorage.getItem('tt-theme');
    if (t === 'light' || t === 'dark' || t === 'system') return t;
  } catch {}
  return 'dark';
}
export const resolveTheme = t => (t === 'system' ? (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark') : t);
export function setTheme(t, persist = true) {
  const eff = resolveTheme(t);
  document.documentElement.dataset.theme = eff;
  const meta = document.querySelector('meta[name=theme-color]');
  if (meta) meta.content = tokens.color[eff].bg;
  if (persist) try { localStorage.setItem('tt-theme', t); } catch {}
}

// Applies the visual preferences: accent preset, font scale, density and motion.
export function applyPrefs(p = {}) {
  const root = document.documentElement;
  const a = ACCENTS[p.accent];
  const custom = a && p.accent !== Object.keys(ACCENTS)[0]; // the first preset is the token default
  for (const [k, v] of Object.entries({
    '--accent': custom ? a.accent : '', '--accent-2': custom ? a.accent_2 : '',
    '--accent-soft': custom ? a.accent + '26' : '', '--grad': custom ? `linear-gradient(135deg,${a.accent},${a.accent_2})` : ''
  })) v ? root.style.setProperty(k, v) : root.style.removeProperty(k);
  root.style.fontSize = p.font_scale && p.font_scale !== 100 ? p.font_scale + '%' : '';
  root.dataset.density = p.density || 'comfortable';
  root.dataset.motion = p.reduce_motion ? 'reduce' : 'full';
}

// Single source of truth for what a tab looks like. The worker's `status` lags behind the user's `desired`,
// so we combine them: expiry wins, then a stop request, then whatever the worker reports.
export function tabState(tab, nowSec) {
  if (tab.expires <= nowSec) return 'expired';
  if (!tab.game) return 'idle'; // rented, no game chosen yet
  if (tab.desired === 'stopped') {
    if (tab.status === 'running' || tab.status === 'queued') return 'stopping';
    return tab.status === 'error' ? 'error' : 'stopped';
  }
  if (tab.status === 'running' || tab.status === 'error') return tab.status;
  return 'queued';
}
export const stateMeta = key => STATUS[key] || STATUS.queued;
export const canRelease = t => t.desired === 'stopped' && ['stopped', 'expired', 'error'].includes(t.status);

// 'midp' = J2ME game in MicroEmulator (240×320 portrait), 'jar' = Java PC game (640×480).
export function tabKind(tab, jars = [], config) {
  if (tab.custom_jar_id) {
    const j = jars.find(x => x.id === tab.custom_jar_id);
    if (j?.kind) return j.kind;
  }
  const g = config?.games.find(x => x.id === tab.game);
  return g && /J2ME/i.test(g.kind) && g.id !== 'custom-jar' ? 'midp' : g?.id === 'custom-jar' ? null : 'jar';
}
