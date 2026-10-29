// Frame + input transport for one tab.
// Viewer: WebSocket stream (JPEG frames drawn to a <canvas>, input as JSON on the same socket),
// with HTTP fallbacks (GET /frame still while connecting, REST input while the socket is closed).
// Multi-screen wall: HTTP polling of /frame.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api, fetchFrame, wsUrl, wsProtocols } from '../api.js';

const EMPTY = { src: '', fresh: false, err: '', w: 0, h: 0 };

export const CLOSE_MESSAGES = {
  4401: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
  4403: 'Kết nối bị từ chối.',
  4404: 'Không tìm thấy tab.',
  4409: 'Tab không chạy (đã dừng hoặc hết hạn).',
  4429: 'Có quá nhiều người đang xem tab này. Thử lại sau.'
};
const FATAL = new Set([4401, 4403, 4404]); // retrying cannot help

/**
 * Live stream of one tab.
 * Returns { canvasRef, info: {phase, message, width, height, kind, fps, ping, hasFrame}, input }.
 * Only the newest frame is kept; decoding/drawing happens in requestAnimationFrame.
 */
export function useTabStream(tabId, { fps, enabled, share }) {
  const canvasRef = useRef(null);
  const wsRef = useRef(null);
  const fpsRef = useRef(fps);
  const pingStart = useRef(0);
  const [info, setInfo] = useState({ phase: 'connecting', message: '', width: 0, height: 0, kind: null, fps: 0, ping: 0, hasFrame: false });
  const patch = p => setInfo(i => ({ ...i, ...p }));

  useEffect(() => {
    if (!enabled) { patch({ phase: 'idle', fps: 0 }); return; }
    let alive = true, retry = 0, retryTimer, raf = 0, decoding = false, latest = null;
    // FPS = frames received in a rolling 1 s window, refreshed every 500 ms.
    let stamps = [], lastPing = 0, hasFrame = false;
    const meter = setInterval(() => {
      const t = performance.now();
      stamps = stamps.filter(x => t - x <= 1000);
      patch({ fps: stamps.length, ping: lastPing });
    }, 500);

    const draw = async () => {
      raf = 0;
      if (decoding || !latest) return;
      const blob = latest;
      latest = null;
      decoding = true;
      try {
        const bmp = await createImageBitmap(blob);
        const c = canvasRef.current;
        if (c && alive) {
          const resized = c.width !== bmp.width || c.height !== bmp.height;
          if (resized) { c.width = bmp.width; c.height = bmp.height; }
          c.getContext('2d').drawImage(bmp, 0, 0);
          // The frame size can change without a new hello (screen rotation): track it from the frames themselves.
          if (!hasFrame || resized) { hasFrame = true; patch({ hasFrame: true, phase: 'live', width: bmp.width, height: bmp.height }); }
        }
        bmp.close?.();
      } catch { /* corrupt frame: skip */ }
      decoding = false;
      if (latest && alive && !raf) raf = requestAnimationFrame(draw);
    };

    const connect = () => {
      if (!alive) return;
      patch({ phase: hasFrame ? 'reconnecting' : 'connecting' });
      // Share links authenticate with ?share=; signed-in viewers in token mode send ['bearer', token] as subprotocols.
      const ws = new WebSocket(wsUrl(`/tabs/${tabId}/stream?fps=${fpsRef.current}${share ? '&share=' + encodeURIComponent(share) : ''}`), share ? undefined : wsProtocols());
      ws.binaryType = 'blob';
      wsRef.current = ws;
      ws.onmessage = e => {
        if (typeof e.data === 'string') {
          let m;
          try { m = JSON.parse(e.data); } catch { return; }
          if (m.type === 'hello') { retry = 0; patch({ phase: hasFrame ? 'live' : 'waiting', kind: m.kind, width: m.width, height: m.height, message: '' }); }
          else if (m.type === 'error') patch({ error: { detail: m.detail || 'Thao tác không hợp lệ.', at: Date.now() } });
          return;
        }
        stamps.push(performance.now());
        if (pingStart.current) { lastPing = Math.round(performance.now() - pingStart.current); pingStart.current = 0; }
        latest = e.data;
        if (!raf) raf = requestAnimationFrame(draw);
      };
      ws.onclose = e => {
        if (wsRef.current === ws) wsRef.current = null;
        if (!alive) return;
        const msg = CLOSE_MESSAGES[e.code] || 'Mất kết nối luồng hình. Đang kết nối lại…';
        if (FATAL.has(e.code)) return patch({ phase: 'closed', message: msg });
        // Backoff: 1s, 2s, 4s … max 10s (4409 may just mean the worker has not started the game yet).
        const wait = Math.min(10000, 1000 * 2 ** retry++);
        patch({ phase: 'reconnecting', message: msg });
        retryTimer = setTimeout(connect, wait);
      };
    };
    connect();
    return () => {
      alive = false;
      clearInterval(meter);
      clearTimeout(retryTimer);
      cancelAnimationFrame(raf);
      const ws = wsRef.current;
      wsRef.current = null;
      ws?.close(1000);
    };
  }, [tabId, enabled, share]);

  const setFps = useCallback(v => {
    fpsRef.current = v;
    const ws = wsRef.current;
    if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'fps', fps: v }));
  }, []);
  useEffect(() => { setFps(fps); }, [fps]);

  // Input goes over the socket when open (≈150 ms), otherwise through the REST endpoints.
  const input = useMemo(() => {
    const rest = restInput(tabId);
    const via = (msg, fallback) => {
      const ws = wsRef.current;
      if (ws?.readyState === WebSocket.OPEN) {
        pingStart.current = performance.now();
        ws.send(JSON.stringify(msg));
        return Promise.resolve();
      }
      // Share links have no session, so there is no REST fallback.
      return share ? Promise.reject(new Error('Đang kết nối lại, thử lại sau giây lát.')) : fallback();
    };
    return {
      key: key => via({ type: 'key', key }, () => rest.key(key)),
      tap: (x, y) => via({ type: 'tap', x, y }, () => rest.tap(x, y)),
      swipe: (x, y, x2, y2) => via({ type: 'tap', x, y, x2, y2 }, () => rest.swipe(x, y, x2, y2)),
      text: text => via({ type: 'text', text }, () => rest.text(text))
    };
  }, [tabId, share]);

  return { canvasRef, info, input };
}

// Polls one tab's frame; the next request starts only after the previous one finished.
// Keeps the last image when the worker has nothing new (404) so the screen never flashes.
export function usePollingFrame(tabId, intervalSec, delayMs = 0, enabled = true) {
  const [frame, setFrame] = useState(EMPTY);
  useEffect(() => {
    if (!enabled) return;
    let alive = true, timer, url = '';
    const ctrl = new AbortController();
    const poll = async () => {
      if (!document.hidden) {
        try {
          const blob = await fetchFrame(tabId, ctrl.signal);
          if (!alive) return;
          if (blob) {
            const next = URL.createObjectURL(blob);
            if (url) URL.revokeObjectURL(url);
            url = next;
            setFrame(f => ({ ...f, src: next, fresh: true, err: '' }));
          } else setFrame(f => ({ ...f, fresh: false, err: '' }));
        } catch (e) {
          if (!alive) return;
          setFrame(f => ({ ...f, fresh: false, err: e.message }));
        }
      }
      if (alive) timer = setTimeout(poll, intervalSec * 1000);
    };
    timer = setTimeout(poll, delayMs);
    return () => { alive = false; ctrl.abort(); clearTimeout(timer); if (url) URL.revokeObjectURL(url); };
  }, [tabId, intervalSec, enabled]);
  const onLoad = e => {
    const { naturalWidth: w, naturalHeight: h } = e.currentTarget;
    setFrame(f => (f.w === w && f.h === h ? f : { ...f, w, h }));
  };
  return [frame, onLoad];
}

// Multi-screen wall: still images only (one stream per tab would be too heavy).
export const useTabFrame = usePollingFrame;

export const restInput = tabId => ({
  key: key => api(`/tabs/${tabId}/input`, 'POST', { key }),
  tap: (x, y) => api(`/tabs/${tabId}/tap`, 'POST', { x, y }),
  swipe: (x, y, x2, y2) => api(`/tabs/${tabId}/tap`, 'POST', { x, y, x2, y2 }),
  text: text => api(`/tabs/${tabId}/text`, 'POST', { text })
});

// Maps a client point on an <img> with object-fit: contain back to natural frame pixels (null if in the letterbox).
export function toFramePoint(el, clientX, clientY) {
  const r = el.getBoundingClientRect();
  const nw = el.naturalWidth || el.width, nh = el.naturalHeight || el.height; // <img> or <canvas>
  if (!nw || !nh) return null;
  const scale = Math.min(r.width / nw, r.height / nh);
  const ox = (r.width - nw * scale) / 2, oy = (r.height - nh * scale) / 2;
  const x = (clientX - r.left - ox) / scale, y = (clientY - r.top - oy) / scale;
  if (x < 0 || y < 0 || x >= nw || y >= nh) return null;
  return { x: Math.min(nw - 1, Math.round(x)), y: Math.min(nh - 1, Math.round(y)) };
}
