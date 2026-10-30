import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Camera, Play, Terminal, MonitorOff, Send, Repeat, RotateCw, RotateCcw, Share2, X, HelpCircle, Maximize2, Minimize2, MoreHorizontal, Keyboard, Gamepad2, Hand } from 'lucide-react';
import { api, serverNow } from '../api.js';
import { POLL, STREAM, tabState, tabKind } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, StateBadge, KindBadge, Segmented, Switch, Menu, useToast } from './ui.jsx';
import { ScreenPicker, changeScreen, rotatedScreen, orientationOf, screenDims } from './ScreenPicker.jsx';
import { useMedia } from '../hooks.js';
import { DPad, NumPad, useKeyboard } from './Keypad.jsx';
import { usePollingFrame, useTabStream, toFramePoint } from './frameSource.js';

const ASCII = /^[\x20-\x7E]{1,64}$/;
const TAP_SLOP = 8; // px of pointer travel below which a gesture is a tap, above it a swipe

// Frame box sized to the game's real orientation (J2ME 240×320 portrait, Java PC 640×480 landscape).
// `media` is the visible <img>/<canvas> (class "screen-media"); with `onTouch`, pointer gestures on it are
// mapped to frame pixels and reported as a tap or a swipe. Feedback (ripple) is local and immediate.
export function Screen({ w, h, kind, media, fresh, onTouch, children, className = '', fit, stretch }) {
  const portrait = w ? h > w : kind === 'midp';
  const start = useRef(null);
  const box = useRef(null);
  // With `fit`, the screen takes the largest size that fits its parent (any aspect ratio, centred), snapping to an
  // integer scale only when that wastes <5% (phones have dense pixels: a smaller integer scale just wastes screen).
  // With `stretch`, it fills the parent completely (aspect ratio not kept).
  const [size, setSize] = useState(null);
  useLayoutEffect(() => {
    const el = fit ? box.current?.parentElement : null;
    if (!el) return;
    const fw = w || (portrait ? 240 : 640), fh = h || (portrait ? 320 : 480);
    const measure = () => {
      // Content box of the stage (minus its padding).
      const cs = getComputedStyle(el);
      const aw = el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
      const ah = el.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
      if (aw <= 0 || ah <= 0) return;
      if (stretch) return setSize({ w: Math.floor(aw), h: Math.floor(ah) });
      const f = Math.min(aw / fw, ah / fh);
      const k = Math.floor(f);
      const sc = k >= 1 && k / f >= 0.95 ? k : f;
      setSize({ w: Math.floor(fw * sc), h: Math.floor(fh * sc) });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [fit, w, h, portrait, stretch]);
  const [ripples, setRipples] = useState([]);
  const target = el => el.querySelector('.screen-media:not([hidden])');
  const ripple = (e, swipe) => {
    const r = e.currentTarget.getBoundingClientRect();
    const id = Math.random();
    setRipples(x => [...x, { id, x: e.clientX - r.left, y: e.clientY - r.top, swipe }]);
    setTimeout(() => setRipples(x => x.filter(y => y.id !== id)), 550);
  };
  const handlers = onTouch && {
    onPointerDown: e => {
      if (e.button !== 0) return;
      const el = target(e.currentTarget);
      const p = el && toFramePoint(el, e.clientX, e.clientY);
      if (!p) return;
      e.preventDefault();
      e.currentTarget.setPointerCapture?.(e.pointerId);
      start.current = { cx: e.clientX, cy: e.clientY, p };
    },
    onPointerUp: e => {
      const s0 = start.current;
      start.current = null;
      if (!s0) return;
      const moved = Math.hypot(e.clientX - s0.cx, e.clientY - s0.cy) > TAP_SLOP;
      ripple(e, moved);
      const el = target(e.currentTarget);
      const end = moved && el ? toFramePoint(el, e.clientX, e.clientY) : null;
      if (moved && end) onTouch(s0.p.x, s0.p.y, end.x, end.y);
      else onTouch(s0.p.x, s0.p.y);
    },
    onPointerCancel: () => { start.current = null; },
    onContextMenu: e => e.preventDefault()
  };
  const style = fit
    ? (size ? { width: size.w, height: size.h } : { visibility: 'hidden' })
    : { aspectRatio: w ? `${w} / ${h}` : portrait ? '3 / 4' : '4 / 3' };
  return (
    <div ref={box} className={`screen ${portrait ? 'portrait' : 'landscape'}${fit ? ' fit' : ''}${stretch ? ' stretch' : ''}${onTouch ? ' touch' : ''} ${className}`} style={style} {...handlers}>
      {media}
      {fresh && <span className="live-tag" aria-label="Đang phát trực tiếp">LIVE</span>}
      {ripples.map(r => <span key={r.id} className={'ripple' + (r.swipe ? ' swipe' : '')} style={{ left: r.x, top: r.y }} aria-hidden />)}
      {children}
    </div>
  );
}

const PHASE_TEXT = { connecting: 'Đang kết nối luồng hình…', waiting: 'Đã kết nối, chờ khung hình đầu tiên…', live: 'Trực tiếp', idle: 'Không có tín hiệu' };

// Short key click (WebAudio) for the "sounds" preference.
let audio;
function click() {
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    const o = audio.createOscillator(), g = audio.createGain(), t = audio.currentTime;
    o.frequency.setValueAtTime(900, t); o.frequency.exponentialRampToValueAtTime(500, t + 0.03);
    g.gain.setValueAtTime(0.06, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.04);
    o.connect(g).connect(audio.destination); o.start(t); o.stop(t + 0.05);
  } catch {}
}
const loadAuto = () => { try { return localStorage.getItem('tt-autorotate') === '1'; } catch { return false; } };

const loadStretch = () => { try { return localStorage.getItem('tt-stretch') === '1'; } catch { return false; } };
const loadPadOff = () => { try { return localStorage.getItem('tt-pad-off') === '1'; } catch { return false; } };
const loadOpacity = () => { try { return Number(localStorage.getItem('tt-pad-opacity')) || 0.55; } catch { return 0.55; } };

export default function Viewer({ tab }) {
  const { close, act, open, jars, admin, config, prefs, setPref } = useApp();
  const toast = useToast();
  const root = useRef(null);
  const state = tabState(tab, serverNow());
  const live = state === 'running' || state === 'queued';
  const [fps, setFps] = useState(() => (STREAM.fps_choices.includes(prefs.default_fps) ? prefs.default_fps : STREAM.default_fps));
  const { canvasRef, info, input } = useTabStream(tab.id, { fps, enabled: live });
  // Still image from GET /frame until the stream delivers its first frame.
  const [still, onStillLoad] = usePollingFrame(tab.id, POLL.frame, 0, live && !info.hasFrame);
  const [text, setText] = useState('');
  const [panel, setPanel] = useState(null); // 'screen' | 'text' | 'more' | null
  const [nums, setNums] = useState(false);  // "123" toggle on short screens / landscape overlay
  const [pending, setPending] = useState(null); // screen id we are rotating to
  const [auto, setAuto] = useState(loadAuto);
  const [opacity, setOpacity] = useState(loadOpacity);
  const [fs, setFs] = useState(false);
  // Touch mode: virtual keys hidden, the player taps/swipes the game itself like on an Android phone.
  const [padOff, setPadOff] = useState(loadPadOff);
  const [stretch, setStretch] = useState(loadStretch);
  const toggleStretch = v => { setStretch(v); try { localStorage.setItem('tt-stretch', v ? '1' : '0'); } catch {} };
  const fsDeclined = useRef(false); // the player left fullscreen on purpose: don't force it back
  const [hintOff, setHintOff] = useState(false); // dismissed rotate suggestion
  const deviceLandscape = useMedia('(orientation: landscape)');
  // Layout modes: wide (side keypad), stacked (phone/tablet portrait), pad (landscape phone: gamepad overlay).
  const padMode = useMedia('(orientation: landscape) and (max-height: 500px)');
  const wide = useMedia('(min-width: 1081px) and (min-height: 501px)');
  const touchDevice = useMedia('(pointer: coarse)');
  const lastErr = useRef(0);
  const kind = info.kind || tabKind(tab, admin?.jars || jars, config);
  const streaming = info.hasFrame && info.phase === 'live';
  const j2me = kind === 'midp';
  const screenId = tab.screen || '240x320';

  // Full-viewport layer: lock page scroll; Esc goes to the game, so closing is the explicit X button.
  useEffect(() => {
    document.body.classList.add('no-scroll');
    document.documentElement.classList.add('no-scroll');
    const prev = document.activeElement;
    root.current?.focus();
    const onFs = () => setFs(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onFs);
    return () => { document.body.classList.remove('no-scroll'); document.documentElement.classList.remove('no-scroll'); document.removeEventListener('fullscreenchange', onFs); if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {}); prev?.focus?.(); };
  }, []);

  const fail = e => { if (Date.now() - lastErr.current > 3000) { lastErr.current = Date.now(); toast(e.message, 'error'); } };
  useEffect(() => { if (info.error) fail({ message: info.error.detail }); }, [info.error?.at]);
  const feedback = () => { if (prefs.haptics) navigator.vibrate?.(12); if (prefs.sounds) click(); };
  const send = useCallback(key => { feedback(); input.key(key).catch(fail); }, [input, prefs.haptics, prefs.sounds]);
  const touch = useCallback((x, y, x2, y2) => { feedback(); (x2 === undefined ? input.tap(x, y) : input.swipe(x, y, x2, y2)).catch(fail); }, [input, prefs.haptics, prefs.sounds]);
  useKeyboard(send, live && panel !== 'text');

  const chooseFps = v => { setFps(v); if (v !== prefs.default_fps) setPref('default_fps', v); };

  // Rotation: PATCH {screen}, then "Đang xoay…" until the stream hello reports the new size.
  const rotate = useCallback(async id => {
    if (!id || id === screenId) return;
    setPending(id);
    setPanel(null);
    if (!(await changeScreen(act, tab, id))) setPending(null);
  }, [screenId, tab.id]);
  useEffect(() => {
    if (!pending) return;
    const [pw, ph] = screenDims(pending);
    if (info.width === pw && info.height === ph && info.phase === 'live') setPending(null);
    const t = setTimeout(() => setPending(null), 90000);
    return () => clearTimeout(t);
  }, [pending, info.width, info.height, info.phase]);
  const deviceOrient = deviceLandscape ? 'landscape' : 'portrait';
  const tabOrient = orientationOf(screenId);
  const mismatch = j2me && live && touchDevice && tabOrient !== deviceOrient;
  // "Tự xoay theo thiết bị": follow device rotation (debounced) while the viewer is open.
  useEffect(() => {
    if (!auto || !mismatch || pending) return;
    const t = setTimeout(() => rotate(rotatedScreen(config.screens, screenId, deviceOrient)), 1500);
    return () => clearTimeout(t);
  }, [auto, mismatch, deviceOrient, pending]);
  const toggleAuto = v => { setAuto(v); try { localStorage.setItem('tt-autorotate', v ? '1' : '0'); } catch {} };
  const setOp = v => { setOpacity(v); try { localStorage.setItem('tt-pad-opacity', String(v)); } catch {} };

  // Fullscreen + orientation lock (iOS has neither for elements: falls back to the CSS full-viewport layout).
  const enterFs = async orient => {
    try {
      await root.current.requestFullscreen?.({ navigationUI: 'hide' });
      await screen.orientation?.lock?.(orient);
    } catch {}
  };
  const toggleFs = async () => {
    if (document.fullscreenElement) { fsDeclined.current = true; try { await document.exitFullscreen(); } catch {} return; }
    fsDeclined.current = false;
    await enterFs(tabOrient === 'landscape' || !j2me ? 'landscape' : 'portrait');
  };
  // Landscape phone (Android): the first touch goes fullscreen, hiding the browser bars, so the game uses the whole
  // screen. Browsers only allow it from a tap. iOS has no element fullscreen: the CSS layout already fills the view.
  useEffect(() => {
    if (!padMode || fs || fsDeclined.current || !root.current?.requestFullscreen) return;
    const el = root.current;
    const go = () => { if (!document.fullscreenElement && !fsDeclined.current) enterFs('landscape'); };
    el.addEventListener('pointerdown', go, { once: true });
    return () => el.removeEventListener('pointerdown', go);
  }, [padMode, fs]);
  const togglePad = () => {
    const v = !padOff;
    setPadOff(v); setNums(false);
    try { localStorage.setItem('tt-pad-off', v ? '1' : '0'); } catch {}
  };
  const padToggle = cls => (
    <Button variant="ghost" className={cls} icon={padOff ? Gamepad2 : Hand} onClick={togglePad} aria-pressed={padOff}
      aria-label={padOff ? 'Hiện phím ảo' : 'Ẩn phím ảo (chơi bằng chạm)'} title={padOff ? 'Hiện phím ảo' : 'Ẩn phím ảo — chơi bằng chạm'} />
  );

  const textOk = ASCII.test(text);
  const sendText = async e => {
    e.preventDefault();
    if (!textOk) return toast('Chỉ gõ được 1–64 ký tự không dấu (ASCII).', 'error');
    try { await input.text(text); setText(''); toast('Đã gửi chữ vào game.', 'success'); } catch (err) { toast(err.message, 'error'); }
  };
  const shot = () => {
    const a = document.createElement('a');
    a.href = info.hasFrame ? canvasRef.current.toDataURL('image/png') : still.src;
    a.download = `thuetab-${tab.name.replace(/\s+/g, '_')}-${Date.now()}.png`;
    a.click();
  };
  const Soft = ({ k, children, className = '' }) => {
    const [down, setDown] = useState(false);
    return (
      <button type="button" className={'softkey' + (down ? ' pressed' : '') + ' ' + className} disabled={!live} aria-label={k === 'F1' ? 'Phím mềm trái (F1)' : 'Phím mềm phải (F2)'}
        onClick={() => { setDown(true); setTimeout(() => setDown(false), 160); send(k); }}>{children}</button>
    );
  };

  const fw = info.hasFrame ? info.width : still.w || info.width, fh = info.hasFrame ? info.height : still.h || info.height;
  const [dw, dh] = j2me ? screenDims(screenId) : [640, 480];
  const media = <>
    <canvas ref={canvasRef} className="screen-media" hidden={!info.hasFrame} aria-label={`Màn hình game của ${tab.name}`} role="img" />
    {!info.hasFrame && still.src && <img src={still.src} onLoad={onStillLoad} alt={`Ảnh tĩnh của ${tab.name}`} className="screen-media stale" draggable={false} />}
  </>;
  const status = !live ? 'Không có tín hiệu' : pending ? 'Đang xoay màn hình…' : PHASE_TEXT[info.phase] || info.message;

  const screenPanel = (
    <div className="v-pop" role="dialog" aria-label="Màn hình">
      <ScreenPicker screens={config.screens} value={screenId} onChange={rotate} compact />
      <Switch label="Tự xoay theo thiết bị" desc="Đổi dọc/ngang khi bạn xoay điện thoại." checked={auto} onChange={toggleAuto} />
      <Switch label="Lấp đầy màn hình" desc="Kéo giãn hình game phủ kín màn hình (không giữ tỷ lệ)." checked={stretch} onChange={toggleStretch} />
    </div>
  );
  const textPanel = (
    <form className="v-pop text-send" onSubmit={sendText}>
      <label htmlFor="game-text">Gõ chữ</label>
      <div className="row gap-sm">
        <input id="game-text" value={text} maxLength={64} onChange={e => setText(e.target.value)} placeholder="Tên đăng nhập, mật khẩu…"
          aria-invalid={text && !textOk ? true : undefined} disabled={!live} autoComplete="off" />
        <Button type="submit" variant="primary" icon={Send} disabled={!live || !text} aria-label="Gửi chữ vào game" />
      </div>
      <small className={text && !textOk ? 'danger' : 'hint'}>{text && !textOk ? 'Chỉ dùng chữ không dấu, số và ký hiệu ASCII.' : 'Gửi vào ô nhập đang chọn trong game.'}</small>
    </form>
  );
  const moreItems = [
    { label: 'Khởi động lại', icon: RotateCcw, onClick: () => act(() => api(`/tabs/${tab.id}/restart`, 'POST'), 'Đang khởi động lại game…'), disabled: !live || !tab.game },
    { label: 'Chia sẻ', icon: Share2, onClick: () => open('share', { tab }) },
    { label: 'Đổi game', icon: Repeat, onClick: () => open('game', { tab, ownerJars: admin && tab.user_id && admin.jars.filter(j => j.user_id === tab.user_id) }) },
    { label: 'Nhật ký', icon: Terminal, onClick: () => open('logs', { tab }) },
    { label: 'Chụp màn hình', icon: Camera, onClick: shot, disabled: !info.hasFrame && !still.src }
  ];

  return (
    <div className="v-scrim">
      <div ref={root} className={'viewer' + (fs ? ' is-fs' : '') + (nums ? ' nums-on' : '') + (padOff ? ' pad-off' : '')} role="dialog" aria-modal="true" aria-label={`Màn chơi ${tab.name}`} tabIndex={-1}
        data-keypad={prefs.keypad_size || 'md'} style={{ '--pad-opacity': opacity }}>
        {!padMode && <header className="v-head">
          <div className="v-title min0">
            <h2 className="ellipsis" title={tab.name}>{tab.name}</h2>
            <div className="viewer-meta">
              <StateBadge state={state} /><KindBadge kind={kind} />
              {j2me && <span className="badge num" style={{ '--c': 'var(--muted)' }}>{screenId.replace('x', '×')}</span>}
              <span className={'live' + (streaming && !pending ? ' on' : '')} role="status">{status}</span>
              {/* Only while the live stream runs: before that the picture is a still and the status says why. */}
              {streaming && prefs.show_fps !== false && <span className="stream-meter num" title="FPS nhận được / độ trễ khứ hồi tới máy chủ"><b>{info.fps}</b> FPS · <b>{info.ping || '—'}</b> ms</span>}
            </div>
          </div>
          <div className="v-head-actions">
            {wide && <span className="v-help" tabIndex={0} role="img" aria-label="Phím tắt: mũi tên, Enter, Esc, F1/F2, Backspace, Space, 0–9, * và #"
              title="Phím tắt: mũi tên, Enter, Esc, F1/F2, Backspace, Space, 0–9, * và #"><HelpCircle size={18} aria-hidden /></span>}
            {padToggle()}
            <Button variant="ghost" icon={fs ? Minimize2 : Maximize2} aria-label={fs ? 'Thoát toàn màn hình' : 'Toàn màn hình'} title={fs ? 'Thoát toàn màn hình' : 'Toàn màn hình'} onClick={toggleFs} />
            <button type="button" className="btn btn-ghost btn-icon" onClick={close} aria-label="Đóng"><X size={20} /></button>
          </div>
        </header>}

        <div className="v-stage">
          <Screen fit stretch={stretch} w={fw || dw} h={fh || dh} kind={kind} media={media} fresh={streaming && !pending} onTouch={live && !pending ? touch : undefined}>
            {(!live || (!info.hasFrame && !still.src) || info.phase === 'closed') && (
              <div className="screen-msg">
                <MonitorOff size={28} aria-hidden />
                <p>{!live ? (state === 'expired' ? 'Tab đã hết hạn.' : state === 'stopping' ? 'Tab đang dừng…' : 'Tab đang tạm dừng.')
                  : info.phase === 'closed' ? info.message : info.message || 'Đang chờ khung hình đầu tiên…'}</p>
                {(state === 'stopped' || state === 'error') && <Button variant="primary" icon={Play} onClick={() => act(() => api('/tabs/' + tab.id, 'PATCH', { desired: 'running' }), 'Đang khởi động tab…')}>Bật tab</Button>}
              </div>
            )}
            {live && pending && <div className="screen-msg"><RotateCw size={28} className="spin" aria-hidden /><p>Đang xoay màn hình sang {pending.replace('x', '×')}…</p></div>}
            {live && !pending && info.hasFrame && info.phase === 'reconnecting' && <span className="screen-banner">{info.message}</span>}
          </Screen>
          {mismatch && !auto && !pending && !hintOff ? (
            <div className="v-chips">
              {mismatch && !auto && !pending && !hintOff && (
                <span className="v-chip">
                  <button type="button" className="v-chip-main" onClick={() => rotate(rotatedScreen(config.screens, screenId, deviceOrient))}>
                    <RotateCw size={14} aria-hidden /> Chuyển sang màn {deviceLandscape ? 'ngang' : 'dọc'}</button>
                  <button type="button" className="v-chip-x" aria-label="Ẩn gợi ý" onClick={() => setHintOff(true)}><X size={14} /></button>
                </span>
              )}
            </div>
          ) : null}
          {/* Landscape phone: gamepad overlays on the sides of the game */}
          {padMode && <>
          {!padOff && <>
          <div className="v-overlay left">
            <DPad onKey={send} disabled={!live} className="pad-dpad" />
          </div>
          <div className="v-overlay right">
            <div className="pad-right">
              <Soft k="F1" className="pad-soft">◤</Soft>
              <Soft k="F2" className="pad-soft">◥</Soft>
              <button type="button" className={'key pad-123' + (nums ? ' on' : '')} aria-pressed={nums} onClick={() => setNums(!nums)}>123</button>
              <button type="button" className="key ok pad-ok" disabled={!live} aria-label="OK (Enter)" onClick={() => send('Return')}>OK</button>
            </div>
            {nums && <NumPad onKey={send} disabled={!live} className="pad-nums" />}
          </div>
          </>}
          <div className="v-overlay top-left">
            {padToggle()}
            <Button variant="ghost" icon={fs ? Minimize2 : Maximize2} aria-label={fs ? 'Thoát toàn màn hình' : 'Toàn màn hình'} onClick={toggleFs} />
            <div className="menu">
              <Button variant="ghost" icon={MoreHorizontal} aria-label="Tuỳ chọn màn chơi" aria-expanded={panel === 'more'} onClick={() => setPanel(panel === 'more' ? null : 'more')} />
            </div>
            <button type="button" className="btn btn-ghost btn-icon" onClick={close} aria-label="Đóng màn chơi"><X size={20} /></button>
          </div>
          </>}
        </div>

        {!padMode && <>
        <div className="v-soft">
          <Soft k="F1">◤ Trái</Soft>
          <button type="button" className={'btn btn-sm v-123' + (nums ? ' on' : '')} aria-pressed={nums} onClick={() => setNums(!nums)}>{nums ? 'D-pad' : '123'}</button>
          <small className="dim v-hint">{padOff ? 'Đang chơi bằng chạm — bấm biểu tượng tay cầm để hiện phím' : 'Chạm / vuốt trên màn hình'}</small>
          <Soft k="F2">Phải ◥</Soft>
        </div>

        {!padOff && <div className="v-pad">
          <DPad onKey={send} disabled={!live} />
          <NumPad onKey={send} disabled={!live} />
          {wide && <div className="v-side-text">{textPanel}<p className="hint">Bàn phím: mũi tên, Enter, Esc, F1/F2, Backspace, Space, 0–9, * và #.</p></div>}
        </div>}

        <footer className="v-foot">
          <Segmented label="Tốc độ khung hình" value={fps} onChange={chooseFps} options={STREAM.fps_choices.map(f => [f, `${f}`])} />
          <span className="grow" />
          {j2me && <Button icon={RotateCw} aria-expanded={panel === 'screen'} onClick={() => setPanel(panel === 'screen' ? null : 'screen')}><span className="v-label">Màn hình</span></Button>}
          {(!wide || padOff) && <Button icon={Keyboard} aria-expanded={panel === 'text'} onClick={() => setPanel(panel === 'text' ? null : 'text')}><span className="v-label">Gõ chữ</span></Button>}
          {wide ? moreItems.map(m => <Button key={m.label} icon={m.icon} onClick={m.onClick} disabled={m.disabled}>{m.label}</Button>)
            : <Menu label="Thêm" items={moreItems} />}
        </footer>
        </>}

        {panel && (
          <div className="v-panel" onClick={e => e.target === e.currentTarget && setPanel(null)}>
            <div className="v-panel-card">
              <div className="row between"><strong>{{ screen: 'Màn hình', text: 'Gõ chữ', more: 'Tuỳ chọn' }[panel]}</strong>
                <button type="button" className="btn btn-ghost btn-icon" aria-label="Đóng" onClick={() => setPanel(null)}><X size={18} /></button></div>
              {panel === 'screen' && screenPanel}
              {panel === 'text' && textPanel}
              {panel === 'more' && (
                <div className="v-pop">
                  <Segmented label="Tốc độ khung hình" value={fps} onChange={chooseFps} options={STREAM.fps_choices.map(f => [f, `${f} FPS`])} />
                  {j2me ? screenPanel : <Switch label="Lấp đầy màn hình" desc="Kéo giãn hình game phủ kín màn hình (không giữ tỷ lệ)." checked={stretch} onChange={toggleStretch} />}
                  <Switch label="Hiện phím ảo" desc="Tắt để chơi bằng cách chạm và vuốt trực tiếp trên màn hình game." checked={!padOff} onChange={togglePad} />
                  {!padOff && <label className="field"><span className="label">Độ trong của phím ảo</span>
                    <input type="range" min="0.25" max="1" step="0.05" value={opacity} onChange={e => setOp(Number(e.target.value))} /></label>}
                  <div className="row gap-sm wrap">
                    <Button icon={Keyboard} onClick={() => setPanel('text')}>Gõ chữ</Button>
                    {moreItems.map(m => <Button key={m.label} icon={m.icon} onClick={() => { setPanel(null); m.onClick(); }} disabled={m.disabled}>{m.label}</Button>)}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
