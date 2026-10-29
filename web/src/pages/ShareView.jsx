import React, { Suspense, lazy, useCallback, useEffect, useRef, useState } from 'react';
const QrCode = lazy(() => import('../components/QrCode.jsx'));
import { Eye, Gamepad2, Clock, MonitorOff, ArrowRight, Link2Off, QrCode as QrIcon } from 'lucide-react';
import { api, dateTime, remaining } from '../api.js';
import { STREAM } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Badge, Spinner, Segmented, useToast, CopyButton } from '../components/ui.jsx';
import { Logo, ThemeToggle } from '../components/Shell.jsx';
import { Screen } from '../components/Viewer.jsx';
import { DPad, NumPad, useKeyboard } from '../components/Keypad.jsx';
import { useTabStream } from '../components/frameSource.js';
import { screenDims } from '../components/ScreenPicker.jsx';

// Public viewer for a share link (#/s/TOKEN): no account needed. Keypad only when the link allows control.
export default function ShareView({ token }) {
  const { user } = useApp();
  const toast = useToast();
  const [s, setS] = useState(null);
  const [err, setErr] = useState('');
  const [fps, setFps] = useState(STREAM.default_fps || 30);
  const [qr, setQr] = useState(false);
  const lastErr = useRef(0);
  useEffect(() => { api('/share/' + encodeURIComponent(token)).then(setS).catch(e => setErr(e.message)); }, [token]);
  const live = !!s && s.desired === 'running' && s.expires > Date.now() / 1000;
  const { canvasRef, info, input } = useTabStream(s?.tab_id || 'none', { fps, enabled: live, share: token });
  const fail = e => { if (Date.now() - lastErr.current > 3000) { lastErr.current = Date.now(); toast(e.message, 'error'); } };
  useEffect(() => { if (info.error) fail({ message: info.error.detail }); }, [info.error?.at]);
  const send = useCallback(k => { input.key(k).catch(fail); }, [input]);
  const touch = useCallback((x, y, x2, y2) => { (x2 === undefined ? input.tap(x, y) : input.swipe(x, y, x2, y2)).catch(fail); }, [input]);
  useKeyboard(send, live && !!s?.can_control);

  const cta = !user && <Button variant="primary" onClick={() => { location.hash = '/register'; }}>Đăng ký ThuêTab <ArrowRight size={16} aria-hidden /></Button>;
  const shell = body => (
    <div className="share-page">
      <header className="share-head"><Logo href="#/" /><div className="row gap-sm push"><ThemeToggle />{cta}</div></header>
      {body}
    </div>
  );
  if (err)
    return shell(
      <div className="share-gone">
        <span className="empty-icon"><Link2Off size={26} aria-hidden /></span>
        <h1>Link chia sẻ không còn hiệu lực</h1>
        <p className="muted">{err} Link có thể đã hết hạn hoặc bị chủ tab thu hồi. Hãy xin chủ tab gửi link mới.</p>
        {!user && <p className="muted">Muốn tự treo game 24/24? Tạo tài khoản ThuêTab chỉ trong vài giây.</p>}
        {cta}
      </div>
    );
  if (!s) return shell(<Spinner label="Đang mở link chia sẻ…" />);
  const [dw, dh] = screenDims(s.screen);
  const fw = info.hasFrame ? info.width : dw, fh = info.hasFrame ? info.height : dh;
  return shell(
    <main className="share-main">
      <div className="share-title">
        <div className="min0">
          <h1 className="ellipsis" title={s.name}>{s.name}</h1>
          <div className="row gap-sm wrap">
            {s.can_control ? <Badge color="success"><Gamepad2 size={12} aria-hidden /> Được điều khiển</Badge> : <Badge color="info"><Eye size={12} aria-hidden /> Chỉ xem</Badge>}
            {s.label && <span className="muted small ellipsis">{s.label}</span>}
            <span className="dim small num" title={dateTime(s.expires)}><Clock size={12} aria-hidden /> Link {remaining(s.expires).toLowerCase()}</span>
            {live && info.hasFrame && <span className="stream-meter num">{info.fps < 3 ? <b>Màn hình tĩnh</b> : <><b>{info.fps}</b> FPS</>}</span>}
          </div>
        </div>
        <div className="row gap-sm wrap">
          <CopyButton value={location.href} label="Sao chép link" />
          <Button size="sm" icon={QrIcon} aria-expanded={qr} onClick={() => setQr(!qr)}>Mã QR</Button>
          <Segmented label="Tốc độ khung hình" value={fps} onChange={setFps} options={STREAM.fps_choices.map(f => [f, `${f} FPS`])} />
        </div>
      </div>
      {qr && <div className="share-qr card card-pad"><Suspense fallback={<Spinner label="" />}><QrCode value={location.href} name="thuetab-link" /></Suspense>
        <p className="muted small">Quét mã để mở link này trên điện thoại khác.</p></div>}
      <div className={'share-body' + (s.can_control ? ' with-pad' : '')}>
        <div className="share-stage">
          <Screen fit w={fw} h={fh} kind="midp" fresh={info.hasFrame && info.phase === 'live'} onTouch={s.can_control && live ? touch : undefined}
            media={<canvas ref={canvasRef} className="screen-media" hidden={!info.hasFrame} aria-label={`Màn hình game ${s.name}`} role="img" />}>
            {(!live || !info.hasFrame) && (
              <div className="screen-msg"><MonitorOff size={28} aria-hidden />
                <p>{!live ? 'Tab đang tạm dừng. Hãy quay lại khi chủ tab bật game.' : info.message || 'Đang kết nối luồng hình…'}</p></div>
            )}
          </Screen>
        </div>
        {s.can_control && (
          <div className="share-pad">
            <DPad onKey={send} disabled={!live} soft />
            <NumPad onKey={send} disabled={!live} />
          </div>
        )}
      </div>
    </main>
  );
}
