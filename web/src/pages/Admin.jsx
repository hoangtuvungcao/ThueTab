import React, { Suspense, lazy, useEffect, useMemo, useRef, useState } from 'react';
import { Search, Users, Server, FileCode, LayoutGrid, ScrollText, Banknote, Wallet, Check, X, Save, Receipt, Download, Plus, Trash2, Pause, Clock, FileText, BarChart3, ChevronLeft, ChevronRight, MessageCircle, TicketPercent, Bell, Gift, Wrench } from 'lucide-react';
import { api, downloadApi, money, dateTime, ago, fileSize, serverNow } from '../api.js';
import { navLabel, tabState, ORDER_STATUS, STATUS, POLL } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Card, Empty, PageHead, Stat, Skeleton, Badge, JarBadge, StateBadge, KindBadge, Menu, Segmented, Field, Modal, useToast } from '../components/ui.jsx';
import DataTable from '../components/DataTable.jsx';
import { Chart } from '../components/Charts.jsx';
import { useAdminRun, ConfirmDialog, AdminForm, DeleteTabDialog, AdminTabMenu, CSV, CSV_LABEL, csvPath } from './adminShared.jsx';
import AdminUser from './AdminUser.jsx';
import { CouponsSection, SupportInbox, BroadcastSection, GrowthSection, MaintenanceSection, useGrowthKpis } from './AdminGrowth.jsx';

const AdminContent = lazy(() => import('./AdminContent.jsx'));
const SystemPanel = lazy(() => import('./AdminSystem.jsx'));

const SECTIONS = [
  ['overview', 'Tổng quan', BarChart3], ['users', 'Người dùng', Users], ['tabs', 'Tab', LayoutGrid], ['jars', 'File JAR', FileCode],
  ['orders', 'Đơn nạp', Receipt], ['support', 'Hỗ trợ', MessageCircle], ['coupons', 'Mã khuyến mãi', TicketPercent], ['notify', 'Thông báo', Bell],
  ['growth', 'Tăng trưởng', Gift], ['maintenance', 'Bảo trì', Wrench], ['workers', 'Máy chủ', Server], ['audit', 'Nhật ký', ScrollText], ['content', 'Nội dung & cài đặt', FileText]
];
const C1 = 'var(--accent)', C2 = 'var(--accent-2)', C3 = 'var(--warn)';

function Dashboard({ admin, kpis }) {
  const [days, setDays] = useState(30);
  const [stats, setStats] = useState(null);
  useEffect(() => { setStats(null); api(`/admin/stats?days=${days}`).then(s => setStats(s.days)).catch(() => setStats([])); }, [days]);
  const s = admin.stats;
  const online = admin.workers.filter(w => w.online).length;
  const sum = k => (stats || []).reduce((a, d) => a + (d[k] || 0), 0);
  return (
    <>
      <div className="stats">
        <Stat icon={Banknote} label="Doanh thu" value={money(s.total_revenue)} hint="Tổng tiền đã nạp" />
        <Stat icon={Wallet} label="Số dư người dùng" value={money(s.total_users_balance)} />
        <Stat icon={Users} label="Người dùng" value={s.users} />
        <Stat icon={LayoutGrid} label="Tab đang chạy" value={`${s.active_tabs}/${s.total_tabs}`} />
        <Stat icon={FileCode} label="JAR chờ duyệt" value={s.pending_jars} tone={s.pending_jars ? 'warn' : undefined} />
        <Stat icon={Server} label="Máy chủ trực tuyến" value={`${online}/${admin.workers.length}`} tone={online ? undefined : 'danger'} />
        <Stat icon={MessageCircle} label="Yêu cầu hỗ trợ mở" value={kpis.tickets ?? '—'} tone={kpis.tickets ? 'warn' : undefined} />
        <Stat icon={TicketPercent} label="Mã khuyến mãi đang chạy" value={kpis.coupons ?? '—'} />
      </div>
      <h2 className="sys-title">Hệ thống <small className="muted">· cập nhật mỗi 5 giây</small></h2>
      <Suspense fallback={<Skeleton variant="rows" count={3} />}><SystemPanel /></Suspense>
      <Card title="Hoạt động" actions={<Segmented label="Khoảng thời gian" value={days} onChange={setDays} options={[[7, '7 ngày'], [30, '30 ngày'], [90, '90 ngày']]} />}>
        {!stats ? <Skeleton variant="rows" count={2} /> : (
          <div className="charts">
            <div>
              <p className="chart-sum"><span>Nạp <b className="num">{money(sum('topup'))}</b></span><span>Chi tiêu <b className="num">{money(sum('spend'))}</b></span></p>
              <Chart title="Nạp tiền và chi tiêu theo ngày" data={stats}
                series={[{ key: 'topup', label: 'Nạp', color: C1, format: money }, { key: 'spend', label: 'Chi tiêu', color: C2, format: money }]} />
            </div>
            <div>
              <p className="chart-sum"><span>Đăng ký <b className="num">{sum('signups')}</b></span><span>Lượt thuê <b className="num">{sum('rentals')}</b></span></p>
              <Chart title="Đăng ký mới và lượt thuê" data={stats}
                series={[{ key: 'signups', label: 'Đăng ký', color: C3, type: 'line' }, { key: 'rentals', label: 'Lượt thuê', color: C1, type: 'line' }]} />
            </div>
          </div>
        )}
      </Card>
    </>
  );
}

function UsersSection({ admin, q, openUser }) {
  const [role, setRole] = useState('all');
  const [stat, setStat] = useState('all');
  const [runningOnly, setRunningOnly] = useState(false);
  const rows = admin.users.filter(u => (role === 'all' || u.role === role) && (stat === 'all' || (stat === 'blocked') === !!u.blocked)
    && (!runningOnly || u.running > 0) && (!q || [u.email, u.name, u.id, u.note].some(v => String(v || '').toLowerCase().includes(q))));
  return (
    <>
      <div className="toolbar">
        <select value={role} onChange={e => setRole(e.target.value)} aria-label="Vai trò"><option value="all">Mọi vai trò</option><option value="user">Người dùng</option><option value="admin">Quản trị</option></select>
        <select value={stat} onChange={e => setStat(e.target.value)} aria-label="Trạng thái"><option value="all">Mọi trạng thái</option><option value="active">Đang hoạt động</option><option value="blocked">Đã khoá</option></select>
        <label className="check"><input type="checkbox" checked={runningOnly} onChange={e => setRunningOnly(e.target.checked)} /> Có tab đang chạy</label>
        <span className="dim small push num">{rows.length} người dùng</span>
      </div>
      <Card pad={false}>
        <DataTable rows={rows} onRowClick={u => openUser(u.id)} initialSort={{ key: 'created', dir: -1 }} columns={[
          { key: 'user', label: 'Người dùng', sort: u => u.email, render: u => (
            <div className="cell-user"><span className="avatar" aria-hidden>{(u.name || u.email)[0].toUpperCase()}</span>
              <div className="min0"><strong className="ellipsis" title={u.name}>{u.name}</strong><small className="muted ellipsis" title={u.email}>{u.email}</small></div>
              {u.role === 'admin' ? <Badge color="info">Admin</Badge> : null}{u.blocked ? <Badge color="danger">Đã khoá</Badge> : null}</div>) },
          { key: 'balance', label: 'Số dư', sort: u => u.balance, render: u => <span className="num">{money(u.balance)}</span>, className: 'right' },
          { key: 'tabs', label: 'Tab', sort: u => u.running * 1000 + u.tabs, render: u => <span className="num">{u.running}/{u.tabs}</span> },
          { key: 'paid', label: 'Đã nạp', sort: u => u.paid, render: u => <span className="num">{money(u.paid)}</span>, className: 'right', hideMobile: true },
          { key: 'last', label: 'Đăng nhập', sort: u => u.last_login, render: u => (u.last_login ? <span title={dateTime(u.last_login)}>{ago(u.last_login)}</span> : <span className="dim">—</span>) },
          { key: 'created', label: 'Ngày tạo', sort: u => u.created, render: u => <span className="num">{dateTime(u.created).split(' ')[1] || dateTime(u.created)}</span>, hideMobile: true }
        ]} />
      </Card>
    </>
  );
}

function TabsSection({ admin, q, email, run, setForm, setDel }) {
  const now = serverNow();
  const [st, setSt] = useState('all');
  const [owner, setOwner] = useState('all');
  const [game, setGame] = useState('all');
  const [sel, setSel] = useState([]);
  const jarName = Object.fromEntries(admin.jars.map(j => [j.id, j.filename]));
  const rows = admin.tabs.map(t => ({ ...t, _state: tabState(t, now) })).filter(t => (st === 'all' || t._state === st) && (owner === 'all' || t.user_id === owner)
    && (game === 'all' || (game === 'none' ? !t.game : !!t.game)) && (!q || [t.name, t.id, email[t.user_id], jarName[t.custom_jar_id], t.worker_id].some(v => String(v || '').toLowerCase().includes(q))));
  const selTabs = admin.tabs.filter(t => sel.includes(t.id));
  const owners = [...new Set(admin.tabs.map(t => t.user_id))];
  return (
    <>
      <div className="toolbar">
        <select value={st} onChange={e => setSt(e.target.value)} aria-label="Trạng thái"><option value="all">Mọi trạng thái</option>{Object.entries(STATUS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}</select>
        <select value={owner} onChange={e => setOwner(e.target.value)} aria-label="Chủ tab"><option value="all">Mọi người dùng</option>{owners.map(id => <option key={id} value={id}>{email[id] || id}</option>)}</select>
        <select value={game} onChange={e => setGame(e.target.value)} aria-label="Game"><option value="all">Mọi game</option><option value="has">Đã chọn game</option><option value="none">Chưa chọn game</option></select>
        {sel.length > 0 && (
          <div className="bulk">
            <span className="num">{sel.length} đã chọn</span>
            <Button size="sm" icon={Pause} onClick={() => run(async () => { for (const t of selTabs.filter(x => x.desired === 'running')) await api('/tabs/' + t.id, 'PATCH', { desired: 'stopped' }); }, `Đã dừng ${sel.length} tab.`).then(() => setSel([]))}>Dừng</Button>
            <Button size="sm" icon={Clock} onClick={() => setForm({ kind: 'extend', target: selTabs })}>Tặng giờ</Button>
            <Button size="sm" variant="ghost" onClick={() => setSel([])}>Bỏ chọn</Button>
          </div>
        )}
      </div>
      <Card pad={false}>
        <DataTable rows={rows} selectable selected={sel} onSelect={setSel} initialSort={{ key: 'created', dir: -1 }} columns={[
          { key: 'name', label: 'Tab', sort: t => t.name, render: t => <div className="min0"><strong className="ellipsis" title={t.name}>{t.name}</strong><small className="muted ellipsis" title={jarName[t.custom_jar_id]}>{t.game ? jarName[t.custom_jar_id] || t.game : 'Chưa chọn game'}</small></div> },
          { key: 'owner', label: 'Chủ', sort: t => email[t.user_id] || '', render: t => <span className="ellipsis" title={email[t.user_id]}>{email[t.user_id] || '—'}</span> },
          { key: 'state', label: 'Trạng thái', sort: t => t._state, render: t => <div className="min0"><StateBadge state={t._state} />{t.error && <small className="danger ellipsis" title={t.error}>{t.error}</small>}</div> },
          { key: 'screen', label: 'Màn hình', render: t => <span className="num">{(t.screen || '').replace('x', '×')}</span>, hideMobile: true },
          { key: 'worker', label: 'Worker', render: t => <code>{t.worker_id}</code>, hideMobile: true },
          { key: 'expires', label: 'Hết hạn', sort: t => t.expires, render: t => <span className="num" title={dateTime(t.expires)}>{dateTime(t.expires)}</span> },
          { key: 'created', label: '', sort: t => t.created, render: t => <AdminTabMenu t={t} run={run} ownerJars={admin.jars.filter(j => j.user_id === t.user_id)}
            onExtend={() => setForm({ kind: 'extend', target: t })} onDelete={() => setDel(t)} />, className: 'right' }
        ]} />
      </Card>
    </>
  );
}

function JarsSection({ admin, q, email, run }) {
  const toast = useToast();
  const [del, setDel] = useState(null);
  const rows = admin.jars.filter(j => !q || [j.filename, j.sha256, email[j.user_id], j.status, j.kind].some(v => String(v || '').toLowerCase().includes(q)));
  return (
    <Card pad={false}>
      <DataTable rows={rows} initialSort={{ key: 'created', dir: -1 }} columns={[
        { key: 'file', label: 'File', sort: j => j.filename, render: j => <div className="min0"><span className="row gap-sm min0"><strong className="ellipsis" title={j.filename}>{j.filename}</strong><KindBadge kind={j.kind} /></span><small className="muted ellipsis" title={j.sha256}>{j.midlet || '—'} · <code>{j.sha256?.slice(0, 10)}</code></small></div> },
        { key: 'owner', label: 'Chủ', sort: j => email[j.user_id] || '', render: j => <span className="ellipsis" title={email[j.user_id]}>{email[j.user_id] || '—'}</span> },
        { key: 'size', label: 'Dung lượng', sort: j => j.file_size, render: j => <span className="num">{fileSize(j.file_size)}</span>, hideMobile: true },
        { key: 'created', label: 'Tải lên', sort: j => j.created, render: j => <span title={dateTime(j.created)}>{ago(j.created)}</span> },
        { key: 'status', label: 'Trạng thái', sort: j => j.status, render: j => <JarBadge status={j.status} /> },
        { key: 'act', label: '', className: 'right', render: j => (
          <div className="row gap-xs end">
            <Button size="sm" variant="ghost" icon={Download} title={`Tải ${j.filename}`} onClick={() => downloadApi(`/admin/jars/${j.id}/download`, j.filename).catch(e => toast(e.message, 'error'))}>Tải về</Button>
            {j.status !== 'approved' && <Button size="sm" icon={Check} onClick={() => run(() => api('/admin/jars/' + j.id, 'PATCH', { status: 'approved' }), 'Đã duyệt.')}>Duyệt</Button>}
            {j.status !== 'rejected' && <Button size="sm" variant="danger-ghost" icon={X} onClick={() => run(() => api('/admin/jars/' + j.id, 'PATCH', { status: 'rejected' }), 'Đã chặn file. Tab dùng file này sẽ dừng.')}>Chặn</Button>}
            <Button size="sm" variant="ghost" icon={Trash2} aria-label={`Xoá ${j.filename}`} onClick={() => setDel(j)} />
          </div>) }
      ]} />
      {del && <ConfirmDialog title={`Xoá "${del.filename}"?`} danger confirmLabel="Xoá file" onClose={() => setDel(null)}
        onConfirm={() => run(() => api('/admin/jars/' + del.id, 'DELETE'), 'Đã xoá file.')}>
        <p className="muted">Tab đang dùng file này sẽ chuyển về "Chưa chọn game".</p></ConfirmDialog>}
    </Card>
  );
}

function OrdersSection({ admin, q, email, run, setForm }) {
  const [f, setF] = useState('pending');
  const orders = admin.orders || [];
  const rows = orders.filter(o => (f === 'all' || o.status === f) && (!q || [o.code, email[o.user_id], o.amount].some(v => String(v || '').toLowerCase().includes(q))));
  return (
    <>
      <div className="chips" role="radiogroup" aria-label="Lọc đơn">
        {[...Object.entries(ORDER_STATUS).map(([k, v]) => [k, v.label]), ['all', 'Tất cả']].map(([v, l]) => (
          <button key={v} type="button" role="radio" aria-checked={f === v} className={'chip' + (f === v ? ' on' : '')} onClick={() => setF(v)}>
            {l} <span className="num">{v === 'all' ? orders.length : orders.filter(o => o.status === v).length}</span></button>
        ))}
      </div>
      <Card pad={false}>
        <DataTable rows={rows} initialSort={{ key: 'created', dir: -1 }} columns={[
          { key: 'code', label: 'Mã đơn', sort: o => o.code, render: o => <code>{o.code}</code> },
          { key: 'user', label: 'Người dùng', sort: o => email[o.user_id] || '', render: o => <span className="ellipsis" title={email[o.user_id]}>{email[o.user_id] || '—'}</span> },
          { key: 'amount', label: 'Số tiền', sort: o => o.amount, render: o => <span className="num">{money(o.amount)}</span>, className: 'right' },
          { key: 'status', label: 'Trạng thái', sort: o => o.status, render: o => { const m = ORDER_STATUS[o.status] || { label: o.status, color: 'dim' }; return <Badge color={m.color}>{m.label}</Badge>; } },
          { key: 'created', label: 'Thời gian', sort: o => o.created, render: o => <span className="num">{dateTime(o.created)}</span>, hideMobile: true },
          { key: 'act', label: '', className: 'right', render: o => o.status === 'paid' ? null : (
            <div className="row gap-xs end">
              <Button size="sm" icon={Check} onClick={() => setForm({ kind: 'confirm', target: o })}>Xác nhận tay</Button>
              {o.status === 'pending' && <Button size="sm" variant="ghost" onClick={() => run(() => api(`/admin/orders/${o.id}/cancel`, 'POST'), 'Đã huỷ đơn.')}>Huỷ</Button>}
            </div>) }
        ]} />
      </Card>
    </>
  );
}

function WorkerRow({ w, run, onRemove }) {
  const [cap, setCap] = useState(w.capacity);
  const [drain, setDrain] = useState(!!w.draining);
  const dirty = cap !== w.capacity || drain !== !!w.draining;
  const pct = Math.min(100, Math.round((w.used / Math.max(1, w.capacity)) * 100));
  return (
    <div className="worker">
      <div className="worker-head">
        <code className="ellipsis" title={w.id}>{w.id}</code>
        {w.online ? <Badge color={w.draining ? 'warn' : 'success'} dot>{w.draining ? 'Đang rút' : 'Trực tuyến'}</Badge> : <Badge color="danger" dot>Ngoại tuyến</Badge>}
      </div>
      <div className="meter wide" title={`${w.used}/${w.capacity}`}><span style={{ width: pct + '%' }} /></div>
      <small className="muted num">{w.used}/{w.capacity} slot · {w.last_seen ? 'liên lạc ' + ago(w.last_seen) : 'chưa kết nối'}{w.memory_mb ? ` · ${w.memory_mb} MB` : ''}</small>
      <div className="row gap-sm wrap">
        <label className="inline-field"><span className="small muted">Sức chứa</span>
          <input type="number" min={1} max={100} value={cap} onChange={e => setCap(Math.max(1, Math.min(100, parseInt(e.target.value, 10) || 1)))} /></label>
        <label className="check"><input type="checkbox" checked={drain} onChange={e => setDrain(e.target.checked)} /> Rút tải</label>
        <span className="push" />
        <Button size="sm" variant="ghost" icon={Trash2} aria-label={`Xoá ${w.id}`} onClick={onRemove} />
        <Button size="sm" icon={Save} disabled={!dirty} onClick={() => run(() => api('/admin/workers/' + w.id, 'PATCH', { capacity: cap, draining: drain }), 'Đã lưu máy chủ.')}>Lưu</Button>
      </div>
    </div>
  );
}

function WorkersSection({ admin, run }) {
  const [add, setAdd] = useState(null);
  const [del, setDel] = useState(null);
  return (
    <>
      <div className="toolbar"><span className="muted small">Máy chủ chạy tab. Rút tải để ngừng nhận tab mới trước khi bảo trì.</span><span className="push" />
        <Button icon={Plus} onClick={() => setAdd({ id: '', capacity: 4 })}>Thêm máy chủ</Button></div>
      {admin.workers.length === 0 ? <Empty icon={Server} title="Chưa có máy chủ nào" /> : (
        <div className="worker-grid">{admin.workers.map(w => <WorkerRow key={w.id + w.capacity + w.draining} w={w} run={run} onRemove={() => setDel(w)} />)}</div>
      )}
      {add && (
        <Modal title="Thêm máy chủ" desc="Máy chủ cần được cấu hình với cùng mã và token để kết nối." onClose={() => setAdd(null)}
          footer={<><Button variant="ghost" onClick={() => setAdd(null)}>Hủy</Button>
            <Button variant="primary" disabled={!/^[a-zA-Z0-9_-]{2,40}$/.test(add.id)} onClick={async () => { if (await run(() => api('/admin/workers', 'POST', add), 'Đã thêm máy chủ.')) setAdd(null); }}>Thêm</Button></>}>
          <div className="stack">
            <Field label="Mã máy chủ" hint="2–40 ký tự: chữ, số, - hoặc _."><input value={add.id} onChange={e => setAdd({ ...add, id: e.target.value.trim() })} data-autofocus /></Field>
            <Field label="Sức chứa (slot)"><input type="number" min={1} max={100} value={add.capacity} onChange={e => setAdd({ ...add, capacity: Math.max(1, Math.min(100, parseInt(e.target.value, 10) || 1)) })} /></Field>
          </div>
        </Modal>
      )}
      {del && <ConfirmDialog title={`Xoá máy chủ ${del.id}?`} danger confirmLabel="Xoá" onClose={() => setDel(null)} onConfirm={() => run(() => api('/admin/workers/' + del.id, 'DELETE'), 'Đã xoá máy chủ.')}>
        <p className="muted">Chỉ xoá được khi máy chủ không còn slot nào.</p></ConfirmDialog>}
    </>
  );
}

// Server-side search + pagination.
function AuditSection({ email }) {
  const [q, setQ] = useState('');
  const [page, setPage] = useState(0);
  const [data, setData] = useState(null);
  const limit = 50;
  const timer = useRef();
  useEffect(() => {
    clearTimeout(timer.current);
    timer.current = setTimeout(() => api(`/admin/audit?q=${encodeURIComponent(q)}&limit=${limit}&offset=${page * limit}`).then(setData).catch(() => setData({ items: [], more: false })), 250);
    return () => clearTimeout(timer.current);
  }, [q, page]);
  return (
    <>
      <div className="toolbar">
        <label className="search"><Search size={16} aria-hidden /><input type="search" placeholder="Tìm hành động, mã…" value={q} onChange={e => { setQ(e.target.value); setPage(0); }} aria-label="Tìm trong nhật ký" /></label>
        <div className="row gap-sm push">
          <Button size="sm" icon={ChevronLeft} aria-label="Trang trước" disabled={page === 0} onClick={() => setPage(page - 1)} />
          <span className="small muted num">Trang {page + 1}</span>
          <Button size="sm" icon={ChevronRight} aria-label="Trang sau" disabled={!data?.more} onClick={() => setPage(page + 1)} />
        </div>
      </div>
      <Card pad={false}>
        {!data ? <div className="card-pad"><Skeleton variant="rows" count={4} /></div> : (
          <DataTable rows={data.items} columns={[
            { key: 'created', label: 'Thời gian', render: a => <span className="num" title={dateTime(a.created)}>{dateTime(a.created)}</span> },
            { key: 'actor', label: 'Người thực hiện', render: a => <span className="ellipsis" title={email[a.actor] || a.actor}>{email[a.actor] || a.actor}</span> },
            { key: 'action', label: 'Hành động', render: a => <code>{a.action}</code> },
            { key: 'target', label: 'Đối tượng', render: a => <span className="ellipsis mono" title={a.target}>{email[a.target] || a.target}</span>, hideMobile: true }
          ]} />
        )}
      </Card>
    </>
  );
}

export default function Admin() {
  const { admin, user, prefs } = useApp();
  const [section, setSection] = useState('overview');
  const [q, setQ] = useState('');
  const [form, setForm] = useState(null);
  const [del, setDel] = useState(null);
  const [userId, setUserId] = useState(null);
  const run = useAdminRun();
  const toast = useToast();
  const kpis = useGrowthKpis();
  const email = useMemo(() => Object.fromEntries((admin?.users || []).map(u => [u.id, u.email])), [admin?.users]);
  if (!admin) return <><PageHead title={navLabel('admin')} /><Skeleton variant="rows" count={5} /></>;
  const needle = q.trim().toLowerCase();
  const pendingOrders = (admin.orders || []).filter(o => o.status === 'pending').length;
  const counts = { users: admin.users.length, tabs: admin.tabs.length, jars: admin.stats.pending_jars || 0, orders: pendingOrders, support: kpis.tickets || 0 };
  const searchable = ['users', 'tabs', 'jars', 'orders'].includes(section);

  return (
    <>
      <PageHead title={navLabel('admin')} desc="Quản lý người dùng, tab, file JAR, thanh toán, máy chủ và nội dung trang.">
        <Menu label="Xuất CSV" items={CSV.map(k => ({ label: `Xuất ${CSV_LABEL[k]} (CSV)`, icon: Download, onClick: () => downloadApi(csvPath(k), `thuetab-${k}.csv`).catch(e => toast(e.message, 'error')) }))} />
      </PageHead>
      <div className="admin-nav">
        <div className="tabs-nav" role="tablist" aria-label="Mục quản trị">
          {SECTIONS.map(([id, label, I]) => (
            <button key={id} type="button" role="tab" aria-selected={section === id} className={section === id ? 'on' : ''} onClick={() => { setSection(id); setQ(''); }}>
              <I size={15} aria-hidden /> {label}{counts[id] ? <span className="tab-count num">{counts[id]}</span> : null}
            </button>
          ))}
        </div>
        {searchable && (
          <label className="search">
            <Search size={16} aria-hidden />
            <input type="search" placeholder="Tìm kiếm…" value={q} onChange={e => setQ(e.target.value)} aria-label="Tìm kiếm" />
          </label>
        )}
      </div>

      {section === 'overview' && <Dashboard admin={admin} kpis={kpis} />}
      {section === 'support' && <SupportInbox />}
      {section === 'coupons' && <CouponsSection email={email} />}
      {section === 'notify' && <BroadcastSection users={admin.users} />}
      {section === 'growth' && <GrowthSection />}
      {section === 'maintenance' && <MaintenanceSection />}
      {section === 'users' && <UsersSection admin={admin} q={needle} openUser={setUserId} />}
      {section === 'tabs' && <TabsSection admin={admin} q={needle} email={email} run={run} setForm={setForm} setDel={setDel} />}
      {section === 'jars' && <JarsSection admin={admin} q={needle} email={email} run={run} />}
      {section === 'orders' && <OrdersSection admin={admin} q={needle} email={email} run={run} setForm={setForm} />}
      {section === 'workers' && <WorkersSection admin={admin} run={run} />}
      {section === 'audit' && <AuditSection email={email} />}
      {section === 'content' && <Suspense fallback={<Skeleton variant="rows" count={4} />}><AdminContent /></Suspense>}

      {form && <AdminForm form={form} email={email} run={run} onClose={() => setForm(null)} />}
      {del && <DeleteTabDialog tab={del} run={run} onClose={() => setDel(null)} />}
      {userId && <AdminUser id={userId} email={email} onClose={() => setUserId(null)} />}
    </>
  );
}
