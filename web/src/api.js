// API origin. Empty (default) = same origin as the page (backend-served dist, Vite dev proxy).
// Set VITE_API_BASE at build time when the front-end is hosted elsewhere, e.g. https://api-thuetab.hidev.dev.
export const API_BASE = (import.meta.env.VITE_API_BASE || '').trim().replace(/\/+$/, '');
// Cookies must travel cross-origin when the API lives on another origin.
const CREDENTIALS = API_BASE ? 'include' : 'same-origin';
/** '/tabs' → '<base>/api/tabs'. Accepts paths with or without the leading '/api'. */
export const apiUrl = p => API_BASE + (p.startsWith('/api/') ? p : '/api' + (p.startsWith('/') ? p : '/' + p));
/** WebSocket URL on the API origin (wss for https). */
export const wsUrl = p => (API_BASE || location.origin).replace(/^http/, 'ws') + (p.startsWith('/api/') ? p : '/api' + p);

// Thin client for the ThuêTab API. Errors carry the backend's Vietnamese `detail` message.
export class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}

let clockOffset = 0; // server time - local time, learned from /status
export const serverNow = () => Math.floor(Date.now() / 1000) + clockOffset;
export const syncClock = serverTime => { if (serverTime) clockOffset = serverTime - Math.floor(Date.now() / 1000); };

async function parse(r) {
  const data = await r.json().catch(() => null);
  if (!r.ok) {
    const d = data?.detail;
    const msg = typeof d === 'string' ? d : Array.isArray(d) ? 'Dữ liệu không hợp lệ.' : r.status === 413 ? 'File quá lớn.' : 'Không thể kết nối đến máy chủ.';
    throw new ApiError(msg, r.status);
  }
  return data;
}

export async function api(path, method = 'GET', body) {
  let r;
  try {
    r = await fetch(apiUrl(path), {
      method,
      credentials: CREDENTIALS,
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined
    });
  } catch {
    throw new ApiError('Mất kết nối mạng. Vui lòng thử lại.', 0);
  }
  return parse(r);
}

export async function uploadJar(file) {
  const r = await fetch(apiUrl('/jars/upload'), {
    method: 'POST',
    credentials: CREDENTIALS,
    headers: { 'X-Filename': encodeURIComponent(file.name), 'Content-Type': 'application/octet-stream' },
    body: file
  });
  return parse(r);
}

// Returns a Blob, or null when the worker has not produced a fresh frame yet (404).
export async function fetchFrame(id, signal) {
  const r = await fetch(apiUrl(`/tabs/${id}/frame`), { credentials: CREDENTIALS, cache: 'no-store', signal });
  if (r.status === 404) return null;
  if (!r.ok) await parse(r);
  return r.blob();
}

export const money = n => new Intl.NumberFormat('vi-VN').format(n || 0) + 'đ';
export const dateTime = s => (s ? new Date(s * 1000).toLocaleString('vi-VN', { hour12: false }) : '—');
export const fileSize = b => (b >= 1048576 ? (b / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(b / 1024)) + ' KB');

export function remaining(expires) {
  const s = expires - serverNow();
  if (s <= 0) return 'Đã hết hạn';
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return `Còn ${d} ngày ${h} giờ`;
  if (h > 0) return `Còn ${h} giờ ${m} phút`;
  return `Còn ${Math.max(1, m)} phút`;
}

export const ago = s => {
  const d = serverNow() - s;
  if (d < 60) return 'vừa xong';
  if (d < 3600) return Math.floor(d / 60) + ' phút trước';
  if (d < 86400) return Math.floor(d / 3600) + ' giờ trước';
  return Math.floor(d / 86400) + ' ngày trước';
};
