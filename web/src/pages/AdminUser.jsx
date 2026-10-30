import React, { useEffect, useRef, useState } from 'react';
import { X, KeyRound, LogOut, Lock, Unlock, Trash2, Save, Download, Coins, Check, AlertTriangle } from 'lucide-react';
import { api, downloadApi, money, dateTime, ago, fileSize, serverNow } from '../api.js';
import { tabState, ORDER_STATUS, POLL } from '../tokens.js';
import { useApp } from '../store.js';
import { usePoll } from '../hooks.js';
import { Button, Badge, StateBadge, JarBadge, KindBadge, Segmented, Field, Skeleton, ErrorBox, CopyButton, Modal, Empty, Alert, Switch } from '../components/ui.jsx';
import { Pager, usePaged } from '../components/DataTable.jsx';
import { useAdminRun, ConfirmDialog, AdminForm, DeleteTabDialog, AdminTabMenu } from './adminShared.jsx';

const TABS = [['profile', 'Hồ sơ'], ['tabs', 'Tab'], ['jars', 'File JAR'], ['wallet', 'Ví'], ['orders', 'Đơn nạp'], ['audit', 'Nhật ký']];

function Profile({ u, run }) {
  const [f, setF] = useState({ name: u.name, email: u.email, role: u.role, max_tabs: u.max_tabs ?? 20, note: u.note || '', trial_approved: !!u.trial_approved });
  useEffect(() => setF({ name: u.name, email: u.email, role: u.role, max_tabs: u.max_tabs ?? 20, note: u.note || '', trial_approved: !!u.trial_approved }), [u.id]);
  const dirty = f.name !== u.name || f.email !== u.email || f.role !== u.role || f.max_tabs !== (u.max_tabs ?? 20) || f.note !== (u.note || '') || f.trial_approved !== !!u.trial_approved;
  const valid = f.name.trim() && f.name.length <= 60 && /^\S+@\S+\.\S+$/.test(f.email) && Number.isInteger(f.max_tabs) && f.max_tabs >= 0 && f.max_tabs <= 200 && f.note.length <= 300;
  const save = () => {
    const body = {};
    for (const k of ['name', 'email', 'role', 'max_tabs', 'note']) if (f[k] !== (k === 'note' ? u.note || '' : k === 'max_tabs' ? u.max_tabs ?? 20 : u[k])) body[k] = typeof f[k] === 'string' ? f[k].trim() : f[k];
    if (f.trial_approved !== !!u.trial_approved) body.trial_approved = f.trial_approved;
    return run(() => api('/admin/users/' + u.id, 'PATCH', body), 'Đã lưu hồ sơ.');
  };
  return (
    <div className="stack">
      <div className="kv-grid">
        <div><small className="muted">Số dư</small><strong className="num">{money(u.balance)}</strong></div>
        <div><small className="muted">Đã nạp</small><strong className="num">{money(u.paid || 0)}</strong></div>
        <div><small className="muted">Tab chạy</small><strong className="num">{u.running || 0}/{u.tabs || 0}</strong></div>
        <div><small className="muted">Phiên đăng nhập</small><strong className="num">{u.sessions || 0}</strong></div>
        <div><small className="muted">Đăng nhập gần nhất</small><strong>{u.last_login ? ago(u.last_login) : '—'}</strong></div>
        <div><small className="muted">Ngày tạo</small><strong className="num">{dateTime(u.created)}</strong></div>
      </div>
      <Field label="Tên hiển thị"><input value={f.name} maxLength={60} onChange={e => setF({ ...f, name: e.target.value })} /></Field>
      <Field label="Email"><input type="email" value={f.email} onChange={e => setF({ ...f, email: e.target.value })} /></Field>
      <div className="field-row">
        <Field label="Vai trò"><select value={f.role} onChange={e => setF({ ...f, role: e.target.value })}><option value="user">Người dùng</option><option value="admin">Quản trị</option></select></Field>
        <Field label="Số tab tối đa" hint="0–200"><input type="number" min={0} max={200} value={f.max_tabs} onChange={e => setF({ ...f, max_tabs: parseInt(e.target.value, 10) || 0 })} /></Field>
      </div>
      <Field label="Ghi chú nội bộ" hint={`${f.note.length}/300 · chỉ quản trị viên thấy`}><textarea rows={3} value={f.note} maxLength={300} onChange={e => setF({ ...f, note: e.target.value })} /></Field>
      <Switch label="Cho phép dùng thử" desc={u.trial_used ? 'Người dùng đã dùng lượt thử.' : 'Một lượt thuê miễn phí theo cấu hình.'} checked={f.trial_approved} disabled={!!u.trial_used} onChange={v => setF({ ...f, trial_approved: v })} />
      <div><Button variant="primary" icon={Save} disabled={!dirty || !valid} onClick={save}>Lưu hồ sơ</Button></div>
    </div>
  );
}

export default function AdminUser({ id, email, onClose }) {
  const { user: me, act, refreshAdmin } = useApp();
  const [d, setD] = useState(null);
  const [err, setErr] = useState('');
  const [tab, setTab] = useState('profile');
  const [form, setForm] = useState(null);
  const [del, setDel] = useState(null);       // tab to force-delete
  const [delJar, setDelJar] = useState(null);
  const pJars = usePaged(d?.jars || []), pLedger = usePaged(d?.ledger || []), pOrders = usePaged(d?.orders || []), pAudit = usePaged(d?.audit || []);
  const [confirm, setConfirm] = useState(null); // 'delete' | 'logout' | 'block' | 'reset'
  const [temp, setTemp] = useState('');
  const gone = useRef(false);
  const load = () => (gone.current ? Promise.resolve() : api('/admin/users/' + id).then(x => { setD(x); setErr(''); }).catch(e => { if (e.status === 404) gone.current = true; setErr(e.message); }));
  useEffect(() => { load(); }, [id]);
  usePoll(load, POLL.data);
  const run = useAdminRun(load);
  useEffect(() => {
    const onKey = e => { if (e.key === 'Escape' && !form && !confirm && !del && !delJar && !temp) onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [form, confirm, del, delJar, temp]);
  const u = d?.user;
  const now = serverNow();
  const self = u && u.id === me.id;

  return (
    <div className="drawer-scrim" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <aside className="drawer" role="dialog" aria-modal="true" aria-label="Chi tiết người dùng">
        <header className="drawer-head">
          {u ? (
            <div className="cell-user min0">
              <span className="avatar" aria-hidden>{(u.name || u.email)[0].toUpperCase()}</span>
              <div className="min0"><h2 className="ellipsis" title={u.name}>{u.name}</h2><small className="muted ellipsis" title={u.email}>{u.email}</small></div>
              {u.role === 'admin' ? <Badge color="info">Admin</Badge> : null}{u.blocked ? <Badge color="danger">Đã khoá</Badge> : null}
            </div>
          ) : <span className="grow" />}
          <button type="button" className="btn btn-ghost btn-icon" onClick={onClose} aria-label="Đóng"><X size={20} /></button>
        </header>
        {err && <div className="drawer-body"><ErrorBox onRetry={load}>{err}</ErrorBox></div>}
        {!d && !err && <div className="drawer-body"><Skeleton variant="rows" count={5} /></div>}
        {u && (
          <>
            <div className="drawer-actions">
              <Button size="sm" icon={Coins} onClick={() => setForm({ kind: 'balance', target: u })}>Số dư</Button>
              <Button size="sm" icon={KeyRound} onClick={() => setConfirm('reset')}>Đặt lại mật khẩu</Button>
              <Button size="sm" icon={LogOut} onClick={() => setConfirm('logout')}>Đăng xuất mọi thiết bị</Button>
              <Button size="sm" icon={u.blocked ? Unlock : Lock} variant={u.blocked ? 'secondary' : 'danger-ghost'} disabled={self}
                onClick={() => (u.blocked ? run(() => api('/admin/users/' + u.id, 'PATCH', { blocked: false }), 'Đã mở khoá.') : setConfirm('block'))}>{u.blocked ? 'Mở khoá' : 'Khoá'}</Button>
            </div>
            <div className="drawer-tabs"><Segmented label="Mục" value={tab} onChange={setTab} options={TABS.map(([k, l]) => [k, l + (k === 'tabs' ? ` ${d.tabs.length}` : k === 'jars' ? ` ${d.jars.length}` : '')])} /></div>
            <div className="drawer-body">
              {tab === 'profile' && <>
                <Profile u={u} run={run} />
                <section className="danger-zone">
                  <h3><AlertTriangle size={16} aria-hidden /> Vùng nguy hiểm</h3>
                  <p className="muted small">Xoá vĩnh viễn tài khoản cùng toàn bộ tab, slot, file JAR, đơn nạp và lịch sử ví. Không thể hoàn tác.</p>
                  <div><Button variant="danger" icon={Trash2} disabled={self} onClick={() => setConfirm('delete')}>Xoá tài khoản</Button></div>
                </section>
              </>}
              {tab === 'tabs' && (d.tabs.length === 0 ? <Empty title="Không có tab" /> : (
                <ul className="drawer-list">
                  {d.tabs.map(t => (
                    <li key={t.id}>
                      <div className="min0 grow"><strong className="ellipsis" title={t.name}>{t.name}</strong>
                        <small className="muted ellipsis">{t.game ? (d.jars.find(j => j.id === t.custom_jar_id)?.filename || t.game) : 'Chưa chọn game'} · {(t.screen || '').replace('x', '×')} · hết hạn {dateTime(t.expires)}</small></div>
                      <StateBadge state={tabState(t, now)} />
                      <AdminTabMenu t={{ ...t, user_id: u.id }} run={run} ownerJars={d.jars} onExtend={() => setForm({ kind: 'extend', target: t })} onDelete={() => setDel(t)} />
                    </li>
                  ))}
                </ul>
              ))}
              {tab === 'jars' && (d.jars.length === 0 ? <Empty title="Không có file JAR" /> : (
                <><ul className="drawer-list">
                  {pJars.rows.map(j => (
                    <li key={j.id}>
                      <div className="min0 grow"><span className="row gap-sm min0"><strong className="ellipsis" title={j.filename}>{j.filename}</strong><KindBadge kind={j.kind} /></span>
                        <small className="muted num">{fileSize(j.file_size)} · {dateTime(j.created)}</small></div>
                      <JarBadge status={j.status} />
                      <Button size="sm" variant="ghost" icon={Download} aria-label={`Tải ${j.filename}`} title="Tải về" onClick={() => downloadApi(`/admin/jars/${j.id}/download`, j.filename).catch(() => {})} />
                      <Button size="sm" variant="ghost" icon={Trash2} aria-label={`Xoá ${j.filename}`} onClick={() => setDelJar(j)} />
                    </li>
                  ))}
                </ul><Pager {...pJars.pager} unit="file" /></>
              ))}
              {tab === 'wallet' && <>
                <div className="row between wrap gap-sm"><span>Số dư hiện tại <b className="num">{money(u.balance)}</b></span><Button size="sm" icon={Coins} onClick={() => setForm({ kind: 'balance', target: u })}>Cộng / trừ tiền</Button></div>
                {d.ledger.length === 0 ? <Empty title="Chưa có giao dịch" /> : (
                  <><ul className="drawer-list">{pLedger.rows.map(l => (
                    <li key={l.id}><div className="min0 grow"><span className="ellipsis" title={l.description}>{l.description}</span><small className="muted num">{dateTime(l.created)}</small></div>
                      <b className={'num amount ' + (l.amount >= 0 ? 'in' : 'out')}>{l.amount >= 0 ? '+' : '−'}{money(Math.abs(l.amount))}</b></li>
                  ))}</ul><Pager {...pLedger.pager} unit="giao dịch" /></>
                )}
              </>}
              {tab === 'orders' && (d.orders.length === 0 ? <Empty title="Chưa có đơn nạp" /> : (
                <><ul className="drawer-list">{pOrders.rows.map(o => {
                  const m = ORDER_STATUS[o.status] || { label: o.status, color: 'dim' };
                  return (
                    <li key={o.id}><div className="min0 grow"><code>{o.code}</code><small className="muted num">{money(o.amount)} · {dateTime(o.created)}</small></div>
                      <Badge color={m.color}>{m.label}</Badge>
                      {o.status !== 'paid' && <Button size="sm" icon={Check} onClick={() => setForm({ kind: 'confirm', target: { ...o, user_id: u.id } })}>Xác nhận</Button>}
                      {o.status === 'pending' && <Button size="sm" variant="ghost" onClick={() => run(() => api(`/admin/orders/${o.id}/cancel`, 'POST'), 'Đã huỷ đơn.')}>Huỷ</Button>}
                    </li>
                  );
                })}</ul><Pager {...pOrders.pager} unit="đơn" /></>
              ))}
              {tab === 'audit' && (d.audit.length === 0 ? <Empty title="Chưa có nhật ký" /> : (
                <><ul className="drawer-list">{pAudit.rows.map((a, i) => (
                  <li key={a.id || i}><code>{a.action}</code><span className="muted ellipsis grow" title={a.target}>{email[a.target] || a.target}</span><small className="muted num" title={dateTime(a.created)}>{ago(a.created)}</small></li>
                ))}</ul><Pager {...pAudit.pager} unit="mục" /></>
              ))}
            </div>
          </>
        )}
      </aside>

      {form && <AdminForm form={form} email={{ ...email, [u?.id]: u?.email }} run={run} onClose={() => setForm(null)} />}
      {del && <DeleteTabDialog tab={del} run={run} onClose={() => setDel(null)} />}
      {delJar && <ConfirmDialog title={`Xoá "${delJar.filename}"?`} danger confirmLabel="Xoá file" onClose={() => setDelJar(null)}
        onConfirm={() => run(() => api('/admin/jars/' + delJar.id, 'DELETE'), 'Đã xoá file.')}><p className="muted">Tab đang dùng file này sẽ chuyển về "Chưa chọn game".</p></ConfirmDialog>}
      {confirm === 'block' && <ConfirmDialog title={`Khoá ${u.email}?`} danger confirmLabel="Khoá tài khoản" onClose={() => setConfirm(null)}
        onConfirm={() => run(() => api('/admin/users/' + u.id, 'PATCH', { blocked: true }), 'Đã khoá tài khoản.')}><p className="muted">Người dùng bị đăng xuất và mọi tab dừng lại. Có thể mở khoá sau.</p></ConfirmDialog>}
      {confirm === 'logout' && <ConfirmDialog title="Đăng xuất mọi thiết bị?" confirmLabel="Đăng xuất" onClose={() => setConfirm(null)}
        onConfirm={() => run(() => api(`/admin/users/${u.id}/logout`, 'POST'), r => `Đã đăng xuất ${r?.sessions ?? 0} phiên.`)}><p className="muted">Tab của người dùng vẫn chạy.</p></ConfirmDialog>}
      {confirm === 'reset' && <ConfirmDialog title={`Đặt lại mật khẩu cho ${u.email}?`} confirmLabel="Tạo mật khẩu tạm" onClose={() => setConfirm(null)}
        onConfirm={async () => { const r = await run(() => api(`/admin/users/${u.id}/password`, 'POST')); if (r?.password) setTemp(r.password); return r; }}>
        <p className="muted">Mật khẩu cũ hết hiệu lực và mọi thiết bị bị đăng xuất. Mật khẩu tạm chỉ hiện một lần.</p></ConfirmDialog>}
      {confirm === 'delete' && <ConfirmDialog title="Xoá tài khoản vĩnh viễn?" danger confirmLabel="Xoá tài khoản" requireText={u.email} onClose={() => setConfirm(null)}
        onConfirm={async () => { const r = await act(() => api('/admin/users/' + u.id, 'DELETE'), `Đã xoá ${u.email}.`); if (r) { await refreshAdmin(); onClose(); } return r; }}>
        <Alert kind="danger" icon={AlertTriangle}>Sẽ xoá <b>{u.email}</b> cùng {d.tabs.length} tab, {d.slots?.length || 0} slot, {d.jars.length} file JAR, {d.orders.length} đơn nạp và toàn bộ lịch sử ví. Không thể hoàn tác.</Alert>
      </ConfirmDialog>}
      {temp && (
        <Modal title="Mật khẩu tạm" desc="Chỉ hiện một lần. Gửi cho người dùng qua kênh an toàn và yêu cầu đổi ngay." onClose={() => setTemp('')}
          footer={<Button variant="primary" onClick={() => setTemp('')}>Đã lưu mật khẩu</Button>}>
          <div className="temp-pass"><code className="num">{temp}</code><CopyButton value={temp} label="Sao chép mật khẩu" /></div>
          <Alert kind="warn" icon={AlertTriangle}>Đóng hộp thoại này sẽ không xem lại được mật khẩu.</Alert>
        </Modal>
      )}
    </div>
  );
}
