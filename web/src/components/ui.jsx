import React, { createContext, useCallback, useContext, useEffect, useId, useRef, useState } from 'react';
import { Check, Copy, Loader2, MoreHorizontal, X, CheckCircle2, AlertTriangle, Info, Gamepad2, Megaphone, Wrench, TicketPercent } from 'lucide-react';
import { api, money, dateTime } from '../api.js';
import { JAR_STATUS, stateMeta, COMPONENTS } from '../tokens.js';

export function Button({ variant = 'secondary', size, icon: Icon, loading, children, className = '', ...rest }) {
  return (
    <button
      type="button"
      className={`btn btn-${variant}${size ? ' btn-' + size : ''}${!children ? ' btn-icon' : ''} ${className}`}
      disabled={loading || rest.disabled}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <Loader2 className="spin" aria-hidden /> : Icon && <Icon aria-hidden />}
      {children != null && children !== false && <span className="btn-label">{children}</span>}
    </button>
  );
}

export const Badge = ({ color = 'dim', dot, children }) => (
  <span className="badge" style={{ '--c': `var(--${color})` }}>
    {dot && <span className="dot" aria-hidden />}
    {children}
  </span>
);

export function StateBadge({ state }) {
  const m = stateMeta(state);
  return <Badge color={m.color} dot>{m.label}</Badge>;
}
export function JarBadge({ status }) {
  const m = JAR_STATUS[status] || JAR_STATUS.pending;
  return <Badge color={m.color}>{m.label}</Badge>;
}

export const KindBadge = ({ kind }) =>
  kind ? <Badge color={kind === 'midp' ? 'info' : 'muted'}>{kind === 'midp' ? 'J2ME' : 'Java PC'}</Badge> : null;

export const Spinner = ({ label = 'Đang tải…' }) => (
  <div className="loading" role="status"><Loader2 size={18} className="spin" aria-hidden /> {label}</div>
);

export const Empty = ({ icon: Icon, title, children, action, image }) => (
  <div className="empty">
    {image ? <img className="empty-img" src={image} width="240" height="180" alt="" aria-hidden /> : Icon && (
      <div className="empty-art" aria-hidden>
        <span className="ring r1" /><span className="ring r2" />
        <span className="empty-icon"><Icon size={26} /></span>
      </div>
    )}
    <strong>{title}</strong>
    {children && <p>{children}</p>}
    {action}
  </div>
);

// Placeholder shapes shown while data loads (instead of a spinner flash).
export const Skeleton = ({ variant = 'cards', count = 3 }) => (
  <div className={`skeleton skeleton-${variant}`} aria-busy="true" aria-label="Đang tải">
    {variant === 'cards' && Array.from({ length: count }, (_, i) => (
      <div key={i} className="sk-card"><div className="sk sk-media" /><div className="sk sk-line w60" /><div className="sk sk-line w40" /><div className="sk sk-btn" /></div>
    ))}
    {variant === 'rows' && Array.from({ length: count }, (_, i) => <div key={i} className="sk sk-row" />)}
  </div>
);

export const ErrorBox = ({ children, onRetry }) => (
  <div className="alert alert-danger" role="alert">
    <AlertTriangle size={16} aria-hidden /> <span>{children}</span>
    {onRetry && <Button size="sm" onClick={onRetry}>Thử lại</Button>}
  </div>
);

export const Alert = ({ kind = 'info', icon: Icon = Info, children }) => (
  <div className={`alert alert-${kind}`}><Icon size={16} aria-hidden /><div>{children}</div></div>
);

export function Field({ label, hint, children }) {
  const id = useId();
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {React.cloneElement(children, { id })}
      {hint && <small className="hint">{hint}</small>}
    </div>
  );
}

export const Card = ({ title, actions, children, className = '', pad = true }) => (
  <section className={`card ${className}`}>
    {(title || actions) && (
      <header className="card-head">
        {title && <h2>{title}</h2>}
        {actions && <div className="row gap-sm">{actions}</div>}
      </header>
    )}
    <div className={pad ? 'card-body' : ''}>{children}</div>
  </section>
);

export const Stat = ({ label, value, hint, icon: Icon, tone }) => (
  <div className="stat">
    <div className="stat-label">{Icon && <Icon size={15} aria-hidden />}{label}</div>
    <div className="stat-value" style={tone ? { color: `var(--${tone})` } : undefined}>{value}</div>
    {hint && <div className="stat-hint">{hint}</div>}
  </div>
);

export const PageHead = ({ title, desc, children }) => (
  <div className="page-head">
    <div><h1>{title}</h1>{desc && <p>{desc}</p>}</div>
    {children && <div className="page-actions">{children}</div>}
  </div>
);

export function Segmented({ value, onChange, options, label }) {
  return (
    <div className="segmented" role="radiogroup" aria-label={label}>
      {options.map(([v, text, Icon]) => (
        <button key={v} type="button" role="radio" aria-checked={value === v} className={value === v ? 'on' : ''}
          onClick={() => onChange(v)} title={Icon ? text : undefined} aria-label={Icon ? text : undefined}>
          {Icon ? <Icon size={16} aria-hidden /> : text}
        </button>
      ))}
    </div>
  );
}

// Generic game glyph (per-game artwork is not shipped).
export const GameIcon = ({ size = 40 }) => (
  <span className="game-icon" style={{ width: size, height: size }} aria-hidden><Gamepad2 size={Math.round(size * 0.5)} /></span>
);

export function Switch({ checked, onChange, label, desc, disabled }) {
  const id = useId();
  return (
    <label className="switch-row" htmlFor={id}>
      <span className="switch-text"><span className="switch-label">{label}</span>{desc && <small className="muted">{desc}</small>}</span>
      <input id={id} type="checkbox" role="switch" checked={!!checked} disabled={disabled} onChange={e => onChange(e.target.checked)} />
      <span className="switch-track" aria-hidden />
    </label>
  );
}

// Site-wide notice from config.site.announcement; dismissal is remembered per text.
export function AnnouncementBar({ text }) {
  const read = () => { try { return localStorage.getItem('tt-ann-dismissed'); } catch { return null; } };
  const [hidden, setHidden] = useState(() => read() === text);
  useEffect(() => setHidden(read() === text), [text]);
  if (!text || hidden) return null;
  return (
    <div className="announce" role="region" aria-label="Thông báo">
      <Megaphone size={16} aria-hidden /><span>{text}</span>
      <button type="button" aria-label="Ẩn thông báo" onClick={() => { try { localStorage.setItem('tt-ann-dismissed', text); } catch {} setHidden(true); }}><X size={16} /></button>
    </div>
  );
}

export function copyText(text) {
  if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text);
  const ta = document.createElement('textarea');
  ta.value = text;
  document.body.appendChild(ta);
  ta.select();
  document.execCommand('copy');
  ta.remove();
  return Promise.resolve();
}

export function CopyButton({ value, label = 'Sao chép' }) {
  const [done, setDone] = useState(false);
  return (
    <Button size="sm" variant="ghost" icon={done ? Check : Copy} aria-label={`${label}: ${value}`} title={label}
      onClick={() => copyText(value).then(() => { setDone(true); setTimeout(() => setDone(false), 1500); })}>
      {done ? 'Đã chép' : null}
    </Button>
  );
}

// Dialog sizes come from tokens.components.dialog.width (sm/md/lg/xl); `wide` is kept as an alias of lg.
export function Modal({ title, desc, onClose, children, footer, wide, size, escClose = true, className = '' }) {
  const sz = size || (wide ? 'lg' : 'md');
  const ref = useRef(null);
  const titleId = useId();
  useEffect(() => {
    const prev = document.activeElement;
    const el = ref.current;
    const first = el.querySelector('[data-autofocus]') || el.querySelector('input:not([type=file]):not([hidden]):not([disabled]),select,textarea,button:not(.modal-x):not(:disabled)');
    first?.focus();
    if (!el.contains(document.activeElement)) el.focus(); // keep keyboard focus (and Esc) inside the dialog
    const onKey = e => { if (escClose && e.key === 'Escape') { e.stopPropagation(); onClose(); } };
    el.addEventListener('keydown', onKey);
    document.body.classList.add('no-scroll');
    return () => { el.removeEventListener('keydown', onKey); document.body.classList.remove('no-scroll'); prev?.focus?.(); };
  }, []);
  return (
    <div className="scrim" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <div ref={ref} className={`modal modal-${sz} ${className}`} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1}>
        <span className="sheet-grip" aria-hidden />
        <header className="modal-head">
          <div><h2 id={titleId}>{title}</h2>{desc && <p>{desc}</p>}</div>
          <button type="button" className="btn btn-ghost btn-icon btn-sm modal-x" onClick={onClose} aria-label="Đóng"><X /></button>
        </header>
        <div className="modal-body">{children}</div>
        {footer && <footer className="modal-foot">{footer}</footer>}
      </div>
    </div>
  );
}

/**
 * Confirmation per tokens.components.confirm: round icon on top, centred title + text, two equal buttons.
 * onConfirm may return false to keep the dialog open.
 */
export function Confirm({ title, children, confirmLabel = 'Xác nhận', cancelLabel = 'Hủy', danger, icon: Icon = danger ? AlertTriangle : Info, onConfirm, onClose, disabled, extra }) {
  const ref = useRef(null);
  const titleId = useId();
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    const prev = document.activeElement;
    const el = ref.current;
    (el.querySelector('[data-autofocus]') || el.querySelector('input,button')).focus();
    const onKey = e => { if (e.key === 'Escape') { e.stopPropagation(); onClose(); } };
    el.addEventListener('keydown', onKey);
    document.body.classList.add('no-scroll');
    return () => { el.removeEventListener('keydown', onKey); document.body.classList.remove('no-scroll'); prev?.focus?.(); };
  }, []);
  const go = async () => { setBusy(true); const r = await onConfirm(); setBusy(false); if (r !== false) onClose(); };
  return (
    <div className="scrim" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <div ref={ref} className={'modal confirm' + (danger ? ' danger' : '')} role="alertdialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1}>
        <span className="sheet-grip" aria-hidden />
        <span className="confirm-icon" aria-hidden><Icon /></span>
        <h2 id={titleId}>{title}</h2>
        {children && <div className="confirm-text">{children}</div>}
        {extra && <div className="confirm-extra">{extra}</div>}
        <div className="confirm-actions">
          <Button onClick={onClose}>{cancelLabel}</Button>
          <Button variant={danger ? 'danger' : 'primary'} loading={busy} disabled={disabled} onClick={go}>{confirmLabel}</Button>
        </div>
      </div>
    </div>
  );
}

// Overflow menu for secondary actions so cards don't show a row of unlabeled icons.
export function Menu({ items, label = 'Thêm thao tác' }) {
  const [open, setOpen] = useState(false);
  const [up, setUp] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    if (!open) return;
    const close = e => { if (!ref.current?.contains(e.target)) setOpen(false); };
    const esc = e => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', close);
    document.addEventListener('keydown', esc);
    ref.current.querySelector('[role=menuitem]:not(:disabled)')?.focus();
    // Open upwards when there is not enough room below (cards near the bottom of the screen).
    const list = ref.current.querySelector('.menu-list');
    if (list) {
      const r = list.getBoundingClientRect();
      const bottomNav = document.querySelector('.bottom-nav')?.getBoundingClientRect().height || 0;
      setUp(r.bottom > innerHeight - bottomNav - 8 && r.height < ref.current.getBoundingClientRect().top - 8);
    }
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', esc); };
  }, [open]);
  const onKey = e => {
    if (!['ArrowDown', 'ArrowUp'].includes(e.key)) return;
    e.preventDefault();
    const list = [...ref.current.querySelectorAll('[role=menuitem]:not(:disabled)')];
    const i = list.indexOf(document.activeElement);
    list[(i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length]?.focus();
  };
  return (
    <div className="menu" ref={ref} onKeyDown={onKey}>
      <Button variant="ghost" icon={MoreHorizontal} aria-label={label} title={label} aria-haspopup="menu" aria-expanded={open} onClick={() => { setUp(false); setOpen(!open); }} />
      {open && (
        <div className={'menu-list' + (up ? ' up' : '')} role="menu">
          {items.filter(Boolean).map((it, i, all) => (
            <React.Fragment key={it.label}>
              {it.danger && i > 0 && !all[i - 1].danger && <hr className="menu-sep" aria-hidden />}
              <button type="button" role="menuitem" disabled={it.disabled} title={it.hint}
                className={it.danger ? 'danger' : ''} onClick={() => { setOpen(false); it.onClick(); }}>
                {it.icon && <it.icon aria-hidden />}<span className="menu-label">{it.label}</span>
              </button>
            </React.Fragment>
          ))}
        </div>
      )}
    </div>
  );
}

const ToastCtx = createContext(() => {});
export const useToast = () => useContext(ToastCtx);
export function ToastProvider({ children }) {
  const [list, setList] = useState([]);
  const push = useCallback((text, kind = 'info') => {
    const id = Math.random();
    const max = COMPONENTS.toast?.max_visible || 3;
    setList(l => [...l.slice(-(max - 1)), { id, text, kind }]);
    setTimeout(() => setList(l => l.filter(t => t.id !== id)), COMPONENTS.toast?.duration_ms || 3500);
  }, []);
  const icons = { success: CheckCircle2, error: AlertTriangle, info: Info };
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {list.map(t => {
          const I = icons[t.kind] || Info;
          return (
            <div key={t.id} className={`toast toast-${t.kind}`}>
              <I size={16} aria-hidden /><span>{t.text}</span>
              <button type="button" aria-label="Đóng thông báo" onClick={() => setList(l => l.filter(x => x.id !== t.id))}><X size={14} /></button>
            </div>
          );
        })}
      </div>
    </ToastCtx.Provider>
  );
}

// System-wide maintenance notice (config.maintenance).
export function MaintenanceBar({ m }) {
  if (!m?.enabled) return null;
  return (
    <div className="maint" role="alert">
      <Wrench size={16} aria-hidden />
      <span><b>Bảo trì:</b> {m.message || 'Hệ thống đang bảo trì.'}{m.until ? ` Dự kiến xong lúc ${dateTime(m.until)}.` : ''}</span>
    </div>
  );
}
export const MAINT_HINT = 'Hệ thống đang bảo trì, tạm thời chưa thể thực hiện.';

/**
 * Promo code input with "Áp dụng". Previews via /coupons/check and reports the applied result to the parent.
 * context 'rent' → {discount, final}; 'topup' → {bonus}. The parent sends `coupon` with its request.
 */
export function CouponField({ context, amount, value, onChange }) {
  const [code, setCode] = useState(value?.code || '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  // Re-check when the amount changes (another plan / quantity).
  useEffect(() => { if (value?.code) apply(value.code); }, [amount]);
  async function apply(c = code) {
    const v = c.trim().toUpperCase();
    if (!v) return;
    setBusy(true);
    setErr('');
    try {
      const r = await api('/coupons/check', 'POST', { code: v, context, amount });
      onChange({ ...r, code: r.code || v });
    } catch (e) { setErr(e.message); onChange(null); }
    setBusy(false);
  }
  return (
    <div className="field coupon">
      <label htmlFor={'cp-' + context}>Mã khuyến mãi</label>
      <div className="row gap-sm">
        <input id={'cp-' + context} value={code} placeholder="Nhập mã nếu có" autoComplete="off" maxLength={32} aria-invalid={err ? true : undefined}
          onChange={e => { setCode(e.target.value.toUpperCase()); setErr(''); if (value) onChange(null); }}
          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); apply(); } }} />
        {value ? <Button icon={X} onClick={() => { setCode(''); onChange(null); }}>Bỏ mã</Button>
          : <Button icon={TicketPercent} loading={busy} disabled={!code.trim()} onClick={() => apply()}>Áp dụng</Button>}
      </div>
      {err && <small className="danger">{err}</small>}
      {value && <small className="success-text">Đã áp dụng {value.code}: {value.message}</small>}
    </div>
  );
}

// "Chrome trên Windows" from a user-agent string.
export function describeAgent(ua = '') {
  const os = /iPhone|iPad|iPod/i.test(ua) ? 'iOS' : /Android/i.test(ua) ? 'Android' : /Windows/i.test(ua) ? 'Windows' : /Mac OS X|Macintosh/i.test(ua) ? 'macOS' : /Linux|X11/i.test(ua) ? 'Linux' : '';
  const br = /ThueTab|Godot/i.test(ua) ? 'Ứng dụng ThuêTab' : /SamsungBrowser/i.test(ua) ? 'Samsung Internet' : /coc_coc|CocCoc/i.test(ua) ? 'Cốc Cốc' : /OPR\/|Opera/i.test(ua) ? 'Opera'
    : /Edg\//i.test(ua) ? 'Edge' : /Firefox|FxiOS/i.test(ua) ? 'Firefox' : /CriOS|Chrome/i.test(ua) ? 'Chrome' : /Safari/i.test(ua) ? 'Safari' : /curl|python|okhttp/i.test(ua) ? 'Công cụ dòng lệnh' : 'Trình duyệt';
  return os ? `${br} trên ${os}` : br;
}
