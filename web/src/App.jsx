import React, { Suspense, lazy, useCallback, useEffect, useMemo, useState } from 'react';
import { api, syncClock, ApiError, clearToken } from './api.js';
import { POLL, loadTheme, setTheme, resolveTheme, applyPrefs } from './tokens.js';
import { usePoll, useRoute } from './hooks.js';
import { AppCtx } from './store.js';
import { ToastProvider, useToast, Spinner, Skeleton, AnnouncementBar, MaintenanceBar } from './components/ui.jsx';
import { Sidebar, Topbar, BottomNav } from './components/Shell.jsx';
import { Dialogs } from './components/Dialogs.jsx';
import Landing from './pages/Landing.jsx';
import AuthDialog from './pages/Auth.jsx';
import Tabs from './pages/Tabs.jsx';
import Jars from './pages/Jars.jsx';
const WalletPage = lazy(() => import('./pages/Wallet.jsx'));
const Plans = lazy(() => import('./pages/Plans.jsx'));
const Help = lazy(() => import('./pages/Help.jsx'));
// Heavier, less-visited pages load on demand to keep the main bundle lean.
const Admin = lazy(() => import('./pages/Admin.jsx'));
const Wall = lazy(() => import('./pages/Wall.jsx'));
const Account = lazy(() => import('./pages/Account.jsx'));
const Settings = lazy(() => import('./pages/Settings.jsx'));
const Download = lazy(() => import('./pages/Download.jsx'));
const Support = lazy(() => import('./pages/Support.jsx'));
const Referral = lazy(() => import('./pages/Referral.jsx'));
const ShareView = lazy(() => import('./pages/ShareView.jsx'));

const PAGES = { tabs: Tabs, jars: Jars, wallet: WalletPage, plans: Plans, help: Help, admin: Admin, wall: Wall, account: Account, settings: Settings, download: Download, support: Support, referral: Referral };

function Root() {
  const toast = useToast();
  const [guestTheme, setGuestTheme] = useState(loadTheme);
  const [localPrefs, setLocalPrefs] = useState(null); // optimistic copy while a save is in flight
  const [config, setConfig] = useState(null);
  const [configError, setConfigError] = useState('');
  const [status, setStatus] = useState(null);
  const [user, setUser] = useState(undefined); // undefined = still checking session
  const [data, setData] = useState({ tabs: null, slots: [], jars: [], wallet: null, loaded: false });
  const [collapsed, setCollapsed] = useState(() => { try { return localStorage.getItem('tt-sidebar') === '1'; } catch { return false; } });
  const [admin, setAdmin] = useState(null);
  const [dialog, setDialog] = useState(null);
  const [auth, setAuth] = useState(null); // 'login' | 'register' | null
  const [route, go] = useRoute('');
  const [base, param] = route.split(/\/(.*)/s); // "support/ID" → ["support", "ID"]
  const [notes, setNotes] = useState({ unread: 0, items: [] });

  // Preferences are synced with the app through /me/prefs; guests only get a local theme.
  const prefs = localPrefs || user?.prefs || {};
  const theme = user ? prefs.theme || 'dark' : guestTheme;
  useEffect(() => {
    setTheme(theme, !user);
    if (theme !== 'system') return;
    const m = matchMedia('(prefers-color-scheme: light)');
    const on = () => setTheme('system', !user);
    m.addEventListener('change', on);
    return () => m.removeEventListener('change', on);
  }, [theme, !user]);
  useEffect(() => applyPrefs(user ? prefs : {}), [JSON.stringify(user ? prefs : {})]);

  const setPref = useCallback(async (key, value) => {
    const prev = localPrefs || user?.prefs || {};
    setLocalPrefs({ ...prev, [key]: value });
    try {
      const me = await api('/me/prefs', 'PATCH', { [key]: value });
      setUser(me);
      setLocalPrefs(null);
    } catch (e) {
      setLocalPrefs(null);
      toast(e.message, 'error');
    }
  }, [user, localPrefs]);

  const loadConfig = () => api('/config').then(c => { setConfig(p => (JSON.stringify(p) === JSON.stringify(c) ? p : c)); setConfigError(''); }).catch(e => setConfigError(e.message));
  const loadStatus = () => api('/status').then(s => { syncClock(s.time); setStatus(p => (p && p.online === s.online && p.accepting === s.accepting ? p : s)); }).catch(() => setStatus({ online: false, accepting: false }));

  const signedOut = () => { setUser(null); setData({ tabs: null, slots: [], jars: [], wallet: null, loaded: false }); setAdmin(null); setDialog(null); };

  const refresh = useCallback(async () => {
    try {
      const [me, tabs, slots, jars, wallet] = await Promise.all([api('/me'), api('/tabs'), api('/slots'), api('/jars'), api('/wallet')]);
      // Polls usually return identical data: keep the previous objects so nothing re-renders.
      setUser(prev => (JSON.stringify(prev) === JSON.stringify(me) ? prev : me));
      setData(prev => {
        const next = { tabs, slots, jars, wallet, loaded: true };
        return JSON.stringify(prev) === JSON.stringify(next) ? prev : next;
      });
      return me;
    } catch (e) {
      if (e instanceof ApiError && (e.status === 401 || e.status === 403)) {
        if (e.status === 403) toast(e.message, 'error');
        signedOut();
      } else if (user === undefined) setUser(null);
    }
  }, [user]);

  const refreshAdmin = useCallback(() => api('/admin/overview').then(setAdmin).catch(e => toast(e.message, 'error')), []);

  useEffect(() => { loadConfig(); loadStatus(); refresh(); }, []);
  // #/register?ref=CODE opens the sign-up form with the referral code.
  useEffect(() => { if (user === null && (base === 'register' || base === 'login')) setAuth(base); }, [user, base]);
  useEffect(() => { if (user?.role === 'admin') refreshAdmin(); }, [user?.id]);

  usePoll(loadStatus, POLL.status);
  usePoll(loadConfig, POLL.status); // picks up maintenance / site changes without a reload
  const loadNotes = useCallback(() => api('/notifications').then(n => setNotes(p => (JSON.stringify(p) === JSON.stringify(n) ? p : n))).catch(() => {}), []);
  useEffect(() => { if (user) loadNotes(); }, [user?.id]);
  usePoll(loadNotes, POLL.data, !!user);
  usePoll(refresh, POLL.data, !!user);
  usePoll(refreshAdmin, route === 'admin' ? POLL.data : POLL.status, user?.role === 'admin');

  // Wraps a mutating call: toast on success/error, then re-sync. Resolves to true on success.
  const act = useCallback(async (fn, okMsg) => {
    try {
      const r = await fn();
      if (okMsg) toast(typeof okMsg === 'function' ? okMsg(r) : okMsg, 'success');
      await refresh();
      return r ?? true;
    } catch (e) {
      toast(e.message, 'error');
      return false;
    }
  }, [refresh]);

  const logout = async () => {
    await api('/auth/logout', 'POST').catch(() => {});
    clearToken();
    signedOut();
    go('');
    toast('Đã đăng xuất.');
  };

  const logoutAll = async () => {
    try { await api('/auth/logout-all', 'POST'); } catch (e) { return toast(e.message, 'error'); }
    clearToken();
    signedOut();
    go('');
    toast('Đã đăng xuất khỏi mọi thiết bị.');
  };

  const ctx = useMemo(() => ({
    config, status, user, admin, theme, prefs, setPref, ...data, refresh, refreshAdmin, act, go, logout, logoutAll,
    reloadConfig: loadConfig, notes, loadNotes, param,
    // Regular users cannot rent, buy slots or upload during maintenance (the API answers 503 anyway).
    maint: !!config?.maintenance?.enabled && user?.role !== 'admin',
    toggleTheme: () => {
      const next = resolveTheme(theme) === 'dark' ? 'light' : 'dark';
      user ? setPref('theme', next) : setGuestTheme(next);
    },
    collapsed,
    toggleSidebar: () => setCollapsed(c => { try { localStorage.setItem('tt-sidebar', c ? '0' : '1'); } catch {} return !c; }),
    open: (type, props = {}) => (user ? setDialog({ type, ...props }) : setAuth('login')),
    close: () => setDialog(null),
    openAuth: setAuth,
    onLogin: me => { setAuth(null); refresh(); if (!route || ['login', 'register', 'download'].includes(base)) go(me.prefs?.start_page || 'tabs'); toast(`Xin chào, ${me.name}!`, 'success'); }
  }), [config, status, user, admin, theme, prefs, setPref, data, refresh, act, route, collapsed, notes, param]);

  if (configError && !config)
    return <div className="boot"><img src="/favicon.svg" width="40" height="40" alt="" /><p>{configError}</p>
      <button className="btn btn-primary" onClick={loadConfig}>Thử lại</button></div>;
  if (!config || user === undefined)
    return <div className="boot"><img src="/favicon.svg" width="40" height="40" alt="" /><Spinner label="Đang kết nối máy chủ…" /></div>;

  // Public share link: works with or without an account.
  if (base === 's' && param)
    return <AppCtx.Provider value={ctx}><Suspense fallback={<div className="boot"><Spinner label="Đang mở link chia sẻ…" /></div>}><ShareView token={param} /></Suspense></AppCtx.Provider>;

  if (!user)
    return (
      <AppCtx.Provider value={ctx}>
        <MaintenanceBar m={config.maintenance} />
        <AnnouncementBar text={config.site?.announcement} />
        <Landing page={base === 'download' ? 'download' : 'home'} />
        {auth && <AuthDialog mode={auth} onClose={() => setAuth(null)} />}
      </AppCtx.Provider>
    );

  const page = PAGES[base] && (base !== 'admin' || user.role === 'admin') ? base : PAGES[prefs.start_page] ? prefs.start_page : 'tabs';
  const Page = PAGES[page];
  return (
    <AppCtx.Provider value={ctx}>
      <div className={'app' + (collapsed ? ' collapsed' : '')}>
        <Sidebar route={page} go={go} />
        <div className="main">
          <MaintenanceBar m={config.maintenance} />
          <AnnouncementBar text={config.site?.announcement} />
          <Topbar go={go} />
          <main className="content" id="main" key={page + (param || '')}>
            <Suspense fallback={<Skeleton variant="cards" />}><Page /></Suspense>
          </main>
        </div>
        <BottomNav route={page} />
      </div>
      <Dialogs dialog={dialog} />
    </AppCtx.Provider>
  );
}

export default function App() {
  return <ToastProvider><Root /></ToastProvider>;
}
