import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useMedia } from '../hooks.js';
import { LayoutGrid, FileCode, Wallet, Tag, LifeBuoy, Shield, Sun, Moon, LogOut, ChevronDown, UserRound, MonitorPlay, Menu, PanelLeftClose, PanelLeftOpen, Settings, Download, MessageCircle, Gift, Bell as BellIcon, CheckCheck, X as XIcon } from 'lucide-react';
import { api, ago, serverNow } from '../api.js';
import { NAV, USER_MENU, resolveTheme } from '../tokens.js';
import { money } from '../api.js';
import { useApp } from '../store.js';
import { useToast } from './ui.jsx';

// tokens.nav icon names → lucide components
export const NAV_ICONS = { 'layout-grid': LayoutGrid, 'monitor-play': MonitorPlay, 'file-code': FileCode, wallet: Wallet, tag: Tag, 'life-buoy': LifeBuoy, shield: Shield, user: UserRound, settings: Settings, download: Download, 'message-circle': MessageCircle, gift: Gift };
// Referral entries disappear when the programme is off.
export const userMenu = config => USER_MENU.filter(m => m.id !== 'referral' || config?.referral?.enabled);

export const navItems = user => NAV.filter(n => !n.admin || user?.role === 'admin');

// Brand: neon gamepad icon + "Thuê" (ink) "Tab" (accent) wordmark.
export const Wordmark = () => <span className="wordmark"><span>Thuê</span><span className="wm-tab">Tab</span></span>;
export function Logo({ onClick, href = '#/' }) {
  return (
    <a className="logo" href={href} onClick={onClick} aria-label="ThuêTab — trang chính">
      <img src="/favicon.svg" width="32" height="32" alt="" />
      <Wordmark />
    </a>
  );
}

// Public /status only says whether the service is up and taking new tabs — nothing about servers.
export function StatusPill() {
  const { status } = useApp();
  const [label, color] = !status ? ['Đang kiểm tra…', 'dim'] : !status.online ? ['Bảo trì', 'danger'] : !status.accepting ? ['Tạm hết chỗ', 'warn'] : ['Sẵn sàng', 'success'];
  return <span className="pill" style={{ '--c': `var(--${color})` }} title="Trạng thái dịch vụ"><span className="dot" />{label}</span>;
}

export function ThemeToggle() {
  const { theme, toggleTheme } = useApp();
  const dark = resolveTheme(theme) === 'dark';
  const label = dark ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối';
  return (
    <button type="button" className="btn btn-ghost btn-icon" onClick={toggleTheme} aria-label={label} title={label}>
      {dark ? <Sun size={18} /> : <Moon size={18} />}
    </button>
  );
}

function UserMenu() {
  const { user, logout, go, config } = useApp();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    if (!open) return;
    const close = e => !ref.current?.contains(e.target) && setOpen(false);
    document.addEventListener('mousedown', close);
    return () => document.removeEventListener('mousedown', close);
  }, [open]);
  const initial = (user.name || user.email)[0].toUpperCase();
  return (
    <div className="menu" ref={ref} onKeyDown={e => e.key === 'Escape' && setOpen(false)}>
      <button type="button" className="user-btn" aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen(!open)} aria-label="Tài khoản">
        <span className="avatar" aria-hidden>{initial}</span>
        <span className="user-name">{user.name}</span>
        <ChevronDown size={14} aria-hidden />
      </button>
      {open && (
        <div className="menu-list" role="menu">
          <div className="menu-info"><strong>{user.name}</strong><small>{user.email}</small>
            {user.role === 'admin' && <small className="accent">Quản trị viên</small>}</div>
          {userMenu(config).map(m => {
            const I = NAV_ICONS[m.icon] || UserRound;
            return <button key={m.id} type="button" role="menuitem" onClick={() => { setOpen(false); go(m.id); }}><I size={16} /> {m.label}</button>;
          })}
          <button type="button" role="menuitem" onClick={logout}><LogOut size={16} /> Đăng xuất</button>
        </div>
      )}
    </div>
  );
}

// Notification bell: unread badge, list, mark read, follow the item's link ("/wallet", "/tabs/ID", "/support/ID").
export function Bell() {
  const { notes, loadNotes, go, tabs, open } = useApp();
  const toast = useToast();
  const [show, setShow] = useState(false);
  const ref = useRef(null);
  const panelRef = useRef(null);
  // On phones the list is a full-screen sheet; the topbar's backdrop-filter would trap a fixed child, so portal it.
  const sheet = useMedia('(max-width: 640px)');
  useEffect(() => {
    if (!show) return;
    loadNotes();
    const close = e => !ref.current?.contains(e.target) && !panelRef.current?.contains(e.target) && setShow(false);
    const esc = e => e.key === 'Escape' && setShow(false);
    document.addEventListener('mousedown', close);
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', esc); };
  }, [show]);
  const markRead = body => api('/notifications/read', 'POST', body).then(loadNotes).catch(() => {});
  const follow = n => {
    setShow(false);
    if (!n.read) markRead({ ids: [n.id] });
    const link = (n.link || '').replace(/^\/?#?\/?/, '');
    if (!link) return;
    const [page, id] = link.split('/');
    if (page === 'tabs' && id) {
      // Old notifications can point at a tab that has since expired or been removed: say so instead of
      // opening an empty game screen. Expired → straight to renewing it; removed → back to the tab list.
      go('tabs');
      const t = tabs?.find(x => x.id === id);
      if (!tabs) return;
      if (!t) toast('Tab này đã bị xóa hoặc giải phóng nên không còn mở được.', 'info');
      else if (t.expires <= serverNow()) { toast(`Tab "${t.name}" đã hết hạn — gia hạn để chơi tiếp.`, 'info'); setTimeout(() => open('renew', { tab: t }), 50); }
      else setTimeout(() => open('viewer', { tab: t }), 50);
    } else go(link);
  };
  const unread = notes.unread || 0;
  return (
    <div className="menu bell" ref={ref}>
      <button type="button" className="btn btn-ghost btn-icon" aria-haspopup="dialog" aria-expanded={show}
        aria-label={unread ? `Thông báo, ${unread} chưa đọc` : 'Thông báo'} title="Thông báo" onClick={() => setShow(!show)}>
        <BellIcon size={18} />{unread > 0 && <span className="bell-badge num">{unread > 99 ? '99+' : unread}</span>}
      </button>
      {show && (sheet ? createPortal : (x => x))((
        <div ref={panelRef} className="menu-list notes" role="dialog" aria-label="Thông báo">
          <span className="sheet-grip" aria-hidden />
          <div className="notes-head"><strong>Thông báo</strong>
            {unread > 0 && <button type="button" className="link" onClick={() => markRead({ all: true })}><CheckCheck size={14} aria-hidden /> Đánh dấu đã đọc tất cả</button>}
            <button type="button" className="btn btn-ghost btn-icon btn-sm notes-x" aria-label="Đóng thông báo" onClick={() => setShow(false)}><XIcon /></button></div>
          {notes.items.length === 0 ? <p className="notes-empty muted"><BellIcon aria-hidden />Chưa có thông báo</p> : (
            <ul className="notes-list">
              {notes.items.map(n => (
                <li key={n.id}>
                  <button type="button" className={'note' + (n.read ? '' : ' unread')} onClick={() => follow(n)}>
                    <span className="note-dot" aria-hidden />
                    <span className="note-text"><strong title={n.title}>{n.title}</strong>{n.body && <span className="note-desc">{n.body}</span>}</span>
                    <small className="note-time num">{ago(n.created)}</small>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      ), document.body)}
    </div>
  );
}

export function Sidebar({ route, go }) {
  const { user, admin, collapsed, toggleSidebar } = useApp();
  return (
    <aside className="sidebar">
      <Logo onClick={e => { e.preventDefault(); go('tabs'); }} />
      <nav aria-label="Điều hướng chính">
        {navItems(user).map(n => {
          const I = NAV_ICONS[n.icon];
          const pending = n.id === 'admin' && admin?.stats?.pending_jars;
          return (
            <a key={n.id} href={'#/' + n.id} className={'nav-link' + (route === n.id ? ' on' : '')} aria-current={route === n.id ? 'page' : undefined} title={n.label}>
              <I size={18} aria-hidden /> <span>{n.label}</span>
              {pending ? <span className="count" title={`${pending} file JAR chờ duyệt`}>{pending}</span> : null}
            </a>
          );
        })}
      </nav>
      <div className="sidebar-foot"><StatusPill /></div>
      <button type="button" className="btn btn-ghost btn-icon collapse-btn" onClick={toggleSidebar}
        aria-label={collapsed ? 'Mở rộng thanh bên' : 'Thu gọn thanh bên'} title={collapsed ? 'Mở rộng thanh bên' : 'Thu gọn thanh bên'}>
        {collapsed ? <PanelLeftOpen size={18} /> : <PanelLeftClose size={18} />}
      </button>
    </aside>
  );
}

export function Topbar({ go }) {
  const { user } = useApp();
  return (
    <header className="topbar">
      <div className="topbar-brand"><Logo onClick={e => { e.preventDefault(); go('tabs'); }} /></div>
      <div className="topbar-right">
        <span className="topbar-status"><StatusPill /></span>
        <button type="button" className="balance" onClick={() => go('wallet')} title="Mở ví">
          <Wallet size={16} aria-hidden /><span className="sr-only">Số dư:</span> {money(user.balance)}
        </button>
        <Bell />
        <span className="topbar-theme"><ThemeToggle /></span>
        <UserMenu />
      </div>
    </header>
  );
}

// Mobile tab bar: the first four nav items, everything else (and account/logout) behind "Thêm".
const BAR_ITEMS = 4;
export function BottomNav({ route }) {
  const { user, logout, go, config, theme, toggleTheme } = useApp();
  const dark = resolveTheme(theme) === 'dark';
  const [more, setMore] = useState(false);
  const items = navItems(user);
  const main = items.slice(0, BAR_ITEMS), rest = items.slice(BAR_ITEMS);
  const restOn = rest.some(n => n.id === route) || userMenu(config).some(m => m.id === route);
  const pick = id => { setMore(false); go(id); };
  return (
    <>
      <nav className="bottom-nav" aria-label="Điều hướng chính">
        {main.map(n => {
          const I = NAV_ICONS[n.icon];
          return (
            <a key={n.id} href={'#/' + n.id} className={route === n.id ? 'on' : ''} aria-current={route === n.id ? 'page' : undefined}>
              <I size={20} aria-hidden /><span>{n.label}</span>
            </a>
          );
        })}
        <button type="button" className={restOn ? 'on' : ''} aria-haspopup="dialog" aria-expanded={more} onClick={() => setMore(true)}>
          <Menu size={20} aria-hidden /><span>Thêm</span>
        </button>
      </nav>
      {more && (
        <div className="sheet-scrim" onClick={() => setMore(false)}>
          <div className="sheet" role="dialog" aria-label="Thêm" onClick={e => e.stopPropagation()}>
            <div className="sheet-handle" aria-hidden />
            <div className="sheet-user"><span className="avatar" aria-hidden>{(user.name || user.email)[0].toUpperCase()}</span>
              <div className="min0"><strong className="ellipsis">{user.name}</strong><small className="muted ellipsis">{user.email}</small></div></div>
            {[...rest, ...userMenu(config)].map(n => {
              const I = NAV_ICONS[n.icon] || UserRound;
              return <button key={n.id} type="button" className={'sheet-item' + (route === n.id ? ' on' : '')} onClick={() => pick(n.id)}><I size={18} aria-hidden /> {n.label}</button>;
            })}
            {/* The header has no room for the theme switch on phones: it lives here (and in Cài đặt). */}
            <button type="button" className="sheet-item" onClick={toggleTheme}>{dark ? <Sun size={18} aria-hidden /> : <Moon size={18} aria-hidden />} {dark ? 'Giao diện sáng' : 'Giao diện tối'}</button>
            <button type="button" className="sheet-item" onClick={() => { setMore(false); logout(); }}><LogOut size={18} aria-hidden /> Đăng xuất</button>
          </div>
        </div>
      )}
    </>
  );
}
