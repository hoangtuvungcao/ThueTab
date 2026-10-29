// Admin: coupons, support inbox, broadcasts, referral growth, maintenance (lazy-loaded with the admin area).
import React, { useEffect, useMemo, useState } from 'react';
import { Plus, Pencil, Trash2, Send, Gift, Wrench, Bell, ArrowLeft, Users } from 'lucide-react';
import { api, money, dateTime, ago } from '../api.js';
import { POLL } from '../tokens.js';
import { useApp } from '../store.js';
import { usePoll } from '../hooks.js';
import { Button, Card, Empty, Badge, Field, Modal, Segmented, Switch, Skeleton, ErrorBox, CopyButton, Alert, Stat, useToast, MaintenanceBar } from '../components/ui.jsx';
import DataTable from '../components/DataTable.jsx';
import { ConfirmDialog } from './adminShared.jsx';
import { TicketThread, TicketBadge, TICKET_STATUS } from './Support.jsx';

const KIND_TEXT = {
  percent: ['Giảm % khi thuê', 'Giảm theo phần trăm giá gói khi thuê, gia hạn hoặc mua slot.'],
  amount: ['Giảm tiền khi thuê', 'Giảm một số tiền cố định khi thuê, gia hạn hoặc mua slot.'],
  topup: ['Thưởng % khi nạp', 'Cộng thêm phần trăm số tiền nạp vào ví.']
};
const toDate = ts => (ts ? new Date(ts * 1000).toISOString().slice(0, 10) : '');
const fromDate = d => (d ? Math.floor(new Date(d + 'T23:59:59').getTime() / 1000) : 0);
const couponText = c => (c.kind === 'amount' ? `−${money(c.value)}` : c.kind === 'percent' ? `−${c.value}%` : `+${c.value}% khi nạp`);

function CouponForm({ initial, onClose, onSaved }) {
  const toast = useToast();
  const editing = !!initial;
  const [f, setF] = useState(initial || { code: '', kind: 'percent', value: 10, max_value: 0, min_amount: 0, max_uses: 0, per_user: 1, expires: 0, active: true, note: '' });
  const [busy, setBusy] = useState(false);
  const set = (k, v) => setF({ ...f, [k]: v });
  const num = (k, max) => <input type="number" inputMode="numeric" min={0} max={max} value={f[k]} onChange={e => set(k, Math.max(0, parseInt(e.target.value, 10) || 0))} />;
  const pct = f.kind !== 'amount';
  const errs = [
    !/^[A-Za-z0-9_-]{3,32}$/.test(f.code) && 'Mã gồm 3–32 ký tự chữ, số, - hoặc _.',
    (f.value < 1 || (pct && f.value > 100) || f.value > 10000000) && (pct ? 'Phần trăm từ 1 đến 100.' : 'Số tiền từ 1đ.'),
    f.note.length > 120 && 'Ghi chú tối đa 120 ký tự.'
  ].filter(Boolean);
  const save = async e => {
    e.preventDefault();
    if (errs.length) return;
    setBusy(true);
    const body = { ...f, code: f.code.toUpperCase() };
    delete body.used; delete body.created;
    try {
      await api(editing ? `/admin/coupons/${initial.code}` : '/admin/coupons', editing ? 'PUT' : 'POST', body);
      toast(editing ? 'Đã lưu mã.' : `Đã tạo mã ${body.code}.`, 'success');
      onSaved();
    } catch (e2) { toast(e2.message, 'error'); }
    setBusy(false);
  };
  return (
    <Modal wide title={editing ? `Sửa mã ${initial.code}` : 'Tạo mã khuyến mãi'} onClose={onClose}
      footer={<><Button variant="ghost" onClick={onClose}>Hủy</Button><Button variant="primary" type="submit" form="coupon-form" loading={busy} disabled={!!errs.length}>{editing ? 'Lưu' : 'Tạo mã'}</Button></>}>
      <form id="coupon-form" className="stack" onSubmit={save}>
        <div className="field-row">
          <Field label="Mã" hint="Người dùng nhập mã này. Không phân biệt hoa/thường."><input value={f.code} disabled={editing} maxLength={32} onChange={e => set('code', e.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, ''))} data-autofocus /></Field>
          <Field label="Ghi chú nội bộ" hint={`${f.note.length}/120`}><input value={f.note} maxLength={120} onChange={e => set('note', e.target.value)} /></Field>
        </div>
        <div className="field"><span className="label">Loại mã</span>
          <div className="choice-grid kind-grid" role="radiogroup" aria-label="Loại mã">
            {Object.entries(KIND_TEXT).map(([k, [t, d]]) => (
              <button key={k} type="button" role="radio" aria-checked={f.kind === k} className={'choice' + (f.kind === k ? ' on' : '')} onClick={() => set('kind', k)}>
                <strong>{t}</strong><small>{d}</small></button>
            ))}
          </div>
        </div>
        <div className="field-row">
          <Field label={pct ? 'Giá trị (%)' : 'Giá trị (đ)'}>{num('value', pct ? 100 : 10000000)}</Field>
          {pct && <Field label="Tối đa (đ)" hint="0 = không giới hạn">{num('max_value', 10000000)}</Field>}
          <Field label={f.kind === 'topup' ? 'Nạp tối thiểu (đ)' : 'Đơn tối thiểu (đ)'} hint="0 = không yêu cầu">{num('min_amount', 10000000)}</Field>
        </div>
        <div className="field-row">
          <Field label="Tổng lượt dùng" hint="0 = không giới hạn">{num('max_uses', 1000000)}</Field>
          <Field label="Lượt mỗi người" hint="0 = không giới hạn">{num('per_user', 1000)}</Field>
          <Field label="Hết hạn" hint="Để trống = không hết hạn"><input type="date" value={toDate(f.expires)} min={toDate(Date.now() / 1000)} onChange={e => set('expires', fromDate(e.target.value))} /></Field>
        </div>
        <Switch label="Đang hoạt động" desc="Tắt để tạm khoá mã mà không xoá." checked={f.active} onChange={v => set('active', v)} />
        {errs.length > 0 && <Alert kind="warn">{errs.join(' ')}</Alert>}
      </form>
    </Modal>
  );
}

export function CouponsSection({ email }) {
  const toast = useToast();
  const [d, setD] = useState(null);
  const [form, setForm] = useState(null); // null | 'new' | coupon
  const [del, setDel] = useState(null);
  const load = () => api('/admin/coupons').then(setD).catch(e => toast(e.message, 'error'));
  useEffect(() => { load(); }, []);
  if (!d) return <Skeleton variant="rows" count={3} />;
  const now = Date.now() / 1000;
  const state = c => (!c.active ? ['Tắt', 'dim'] : c.expires && c.expires <= now ? ['Hết hạn', 'warn'] : c.max_uses && c.used >= c.max_uses ? ['Hết lượt', 'warn'] : ['Đang chạy', 'success']);
  return (
    <>
      <div className="toolbar"><span className="muted small">Mã giảm giá khi thuê và mã thưởng khi nạp tiền.</span><span className="push" />
        <Button variant="primary" icon={Plus} onClick={() => setForm('new')}>Tạo mã</Button></div>
      <Card pad={false}>
        <DataTable rows={d.coupons} rowKey={c => c.code} empty="Chưa có mã khuyến mãi" initialSort={{ key: 'created', dir: -1 }} columns={[
          { key: 'code', label: 'Mã', sort: c => c.code, render: c => <span className="row gap-xs"><code className="strong">{c.code}</code><CopyButton value={c.code} label="Sao chép mã" /></span> },
          { key: 'kind', label: 'Ưu đãi', render: c => <div className="min0"><strong className="num">{couponText(c)}</strong><small className="muted">{KIND_TEXT[c.kind]?.[0]}{c.max_value ? ` · tối đa ${money(c.max_value)}` : ''}</small></div> },
          { key: 'used', label: 'Đã dùng', sort: c => c.used, render: c => <span className="num">{c.used}{c.max_uses ? `/${c.max_uses}` : ''}</span> },
          { key: 'expires', label: 'Hết hạn', sort: c => c.expires || Infinity, render: c => <span className="num">{c.expires ? dateTime(c.expires) : 'Không'}</span>, hideMobile: true },
          { key: 'state', label: 'Trạng thái', render: c => { const [l, col] = state(c); return <Badge color={col}>{l}</Badge>; } },
          { key: 'created', label: '', sort: c => c.created, className: 'right', render: c => (
            <div className="row gap-xs end">
              <Button size="sm" variant="ghost" icon={Pencil} aria-label={`Sửa ${c.code}`} onClick={() => setForm(c)} />
              <Button size="sm" variant="ghost" icon={Trash2} aria-label={`Xoá ${c.code}`} onClick={() => setDel(c)} />
            </div>) }
        ]} />
      </Card>
      <Card title="Lịch sử dùng mã" pad={false}>
        <DataTable rows={d.uses} rowKey={u => u.code + u.created + u.user_id} empty="Chưa có lượt dùng" columns={[
          { key: 'code', label: 'Mã', render: u => <code>{u.code}</code> },
          { key: 'user', label: 'Người dùng', render: u => <span className="ellipsis" title={email[u.user_id]}>{email[u.user_id] || u.user_id}</span> },
          { key: 'ctx', label: 'Dùng khi', render: u => (u.context === 'topup' ? 'Nạp tiền' : 'Thuê / gia hạn') },
          { key: 'amount', label: 'Giá trị', render: u => <span className="num">{money(u.amount)}</span>, className: 'right' },
          { key: 'created', label: 'Thời gian', render: u => <span className="num">{dateTime(u.created)}</span>, hideMobile: true }
        ]} />
      </Card>
      {form && <CouponForm initial={form === 'new' ? null : form} onClose={() => setForm(null)} onSaved={() => { setForm(null); load(); }} />}
      {del && <ConfirmDialog title={`Xoá mã ${del.code}?`} danger confirmLabel="Xoá mã" onClose={() => setDel(null)}
        onConfirm={async () => { try { await api('/admin/coupons/' + del.code, 'DELETE'); toast('Đã xoá mã.', 'success'); load(); return true; } catch (e) { toast(e.message, 'error'); return false; } }}>
        <p className="muted">Lịch sử dùng mã vẫn được giữ lại.</p></ConfirmDialog>}
    </>
  );
}

export function SupportInbox() {
  const [status, setStatus] = useState('open');
  const [list, setList] = useState(null);
  const [open, setOpen] = useState(null);
  const load = () => api('/admin/tickets' + (status === 'all' ? '' : `?status=${status}`)).then(setList).catch(() => setList([]));
  useEffect(() => { setList(null); load(); }, [status]);
  usePoll(load, POLL.status);
  if (open) return <TicketThread id={open} staff onBack={() => { setOpen(null); load(); }} onChange={load} />;
  return (
    <>
      <Segmented label="Trạng thái" value={status} onChange={setStatus} options={[...Object.entries(TICKET_STATUS).map(([k, [l]]) => [k, l]), ['all', 'Tất cả']]} />
      <Card pad={false}>
        {!list ? <div className="card-pad"><Skeleton variant="rows" count={3} /></div> : (
          <DataTable rows={list} onRowClick={t => setOpen(t.id)} empty="Không có yêu cầu nào" columns={[
            { key: 'subject', label: 'Yêu cầu', render: t => <div className="min0"><strong className="ellipsis" title={t.subject}>{t.subject}</strong><small className="muted ellipsis">{t.email || t.user_id}</small></div> },
            { key: 'n', label: 'Tin nhắn', render: t => <span className="num">{t.messages_count}</span> },
            { key: 'status', label: 'Trạng thái', render: t => <TicketBadge s={t.status} /> },
            { key: 'updated', label: 'Cập nhật', sort: t => t.updated, render: t => <span title={dateTime(t.updated)}>{ago(t.updated)}</span> }
          ]} />
        )}
      </Card>
    </>
  );
}

export function BroadcastSection({ users }) {
  const toast = useToast();
  const [f, setF] = useState({ title: '', body: '', link: '', to: 'all', email: '' });
  const [busy, setBusy] = useState(false);
  const target = f.to === 'one' ? users.find(u => u.email.toLowerCase() === f.email.trim().toLowerCase()) : null;
  const valid = f.title.trim() && f.title.length <= 120 && f.body.length <= 500 && f.link.length <= 120 && (f.to === 'all' || target);
  const send = async e => {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    try {
      const r = await api('/admin/notifications', 'POST', { title: f.title.trim(), body: f.body.trim(), link: f.link.trim(), user_id: target?.id });
      toast(`Đã gửi tới ${r.sent} người dùng.`, 'success');
      setF({ ...f, title: '', body: '', link: '' });
    } catch (e2) { toast(e2.message, 'error'); }
    setBusy(false);
  };
  return (
    <div className="editor-grid">
      <Card title="Gửi thông báo">
        <form className="stack" onSubmit={send}>
          <Segmented label="Người nhận" value={f.to} onChange={v => setF({ ...f, to: v })} options={[['all', 'Tất cả người dùng'], ['one', 'Một người']]} />
          {f.to === 'one' && (
            <Field label="Email người nhận" hint={f.email && !target ? 'Không tìm thấy người dùng này.' : target ? `→ ${target.name}` : ''}>
              <input type="email" list="user-emails" value={f.email} onChange={e => setF({ ...f, email: e.target.value })} />
            </Field>
          )}
          <datalist id="user-emails">{users.map(u => <option key={u.id} value={u.email}>{u.name}</option>)}</datalist>
          <Field label="Tiêu đề" hint={`${f.title.length}/120`}><input value={f.title} maxLength={120} onChange={e => setF({ ...f, title: e.target.value })} /></Field>
          <Field label="Nội dung" hint={`${f.body.length}/500`}><textarea rows={3} value={f.body} maxLength={500} onChange={e => setF({ ...f, body: e.target.value })} /></Field>
          <Field label="Liên kết (tuỳ chọn)" hint="Trang mở khi bấm, ví dụ /wallet, /plans, /support"><input value={f.link} maxLength={120} placeholder="/wallet" onChange={e => setF({ ...f, link: e.target.value })} /></Field>
          <div><Button variant="primary" type="submit" icon={Send} loading={busy} disabled={!valid}>Gửi thông báo</Button></div>
        </form>
      </Card>
      <div className="preview-col">
        <small className="muted">Xem trước trong chuông thông báo</small>
        <div className="preview notes-preview">
          <div className="note unread"><span className="note-dot" aria-hidden />
            <span className="note-text"><strong>{f.title || 'Tiêu đề thông báo'}</strong>{f.body && <span className="note-desc">{f.body}</span>}</span><small className="note-time">vừa xong</small></div>
        </div>
      </div>
    </div>
  );
}

export function GrowthSection() {
  const { reloadConfig } = useApp();
  const toast = useToast();
  const [g, setG] = useState(null);
  const [r, setR] = useState(null);
  const [busy, setBusy] = useState(false);
  const load = () => api('/admin/growth').then(x => { setG(x); setR(x.referral); }).catch(e => toast(e.message, 'error'));
  useEffect(() => { load(); }, []);
  if (!g) return <Skeleton variant="rows" count={3} />;
  const dirty = JSON.stringify(r) !== JSON.stringify(g.referral);
  const valid = r.percent >= 0 && r.percent <= 50 && r.max_bonus >= 0 && r.max_bonus <= 5000000 && r.referee_bonus >= 0 && r.referee_bonus <= 1000000;
  const save = async () => {
    setBusy(true);
    try { await api('/admin/settings/referral', 'PUT', r); toast('Đã lưu chương trình giới thiệu.', 'success'); await load(); reloadConfig(); }
    catch (e) { toast(e.message, 'error'); }
    setBusy(false);
  };
  const n = (k, max) => <input type="number" inputMode="numeric" min={0} max={max} value={r[k]} onChange={e => setR({ ...r, [k]: Math.max(0, parseInt(e.target.value, 10) || 0) })} />;
  return (
    <div className="two-col">
      <Card title="Chương trình giới thiệu">
        <Switch label="Bật chương trình" desc="Tắt để ẩn mục Giới thiệu bạn bè với mọi người dùng." checked={r.enabled} onChange={v => setR({ ...r, enabled: v })} />
        <div className="field-row">
          <Field label="Thưởng người mời (%)" hint="0–50% số tiền nạp lần đầu của bạn bè">{n('percent', 50)}</Field>
          <Field label="Thưởng tối đa (đ)" hint="Mỗi người được mời">{n('max_bonus', 5000000)}</Field>
          <Field label="Quà người mới (đ)" hint="Cộng cho người đăng ký bằng mã">{n('referee_bonus', 1000000)}</Field>
        </div>
        <p className="muted small">Ví dụ: bạn bè nạp 100.000đ lần đầu → người mời nhận {money(Math.min(100000 * r.percent / 100, r.max_bonus || Infinity))}.</p>
        <div><Button variant="primary" loading={busy} disabled={!dirty || !valid} onClick={save}>Lưu</Button></div>
      </Card>
      <Card title="Người giới thiệu hàng đầu" pad={false}>
        {g.top_referrers.length === 0 ? <Empty icon={Users} title="Chưa có ai mời bạn bè" /> : (
          <ol className="drawer-list pad-list rank-list">
            {g.top_referrers.map((x, i) => <li key={x.user_id}><span className="rank num">{i + 1}</span><span className="ellipsis grow" title={x.email}>{x.email}</span><b className="num">{x.invited}</b><small className="muted">người</small></li>)}
          </ol>
        )}
      </Card>
    </div>
  );
}

export function MaintenanceSection() {
  const { reloadConfig } = useApp();
  const toast = useToast();
  const [m, setM] = useState(null);
  const [saved, setSaved] = useState(null);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => { api('/admin/growth').then(x => { setM(x.maintenance); setSaved(x.maintenance); }).catch(e => toast(e.message, 'error')); }, []);
  if (!m) return <Skeleton variant="rows" count={2} />;
  const toLocal = ts => (ts ? new Date(ts * 1000 - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : '');
  const save = async next => {
    setBusy(true);
    try {
      const v = await api('/admin/settings/maintenance', 'PUT', next);
      setM(v); setSaved(v); reloadConfig();
      toast(v.enabled ? 'Đã bật chế độ bảo trì.' : 'Đã tắt chế độ bảo trì.', 'success');
    } catch (e) { toast(e.message, 'error'); }
    setBusy(false);
  };
  const dirty = JSON.stringify(m) !== JSON.stringify(saved);
  return (
    <div className="two-col">
      <Card title="Chế độ bảo trì">
        <p className="muted small">Khi bật, mọi trang hiện thông báo bảo trì; người dùng thường không thể thuê tab, mua slot hay tải file JAR. Tab đang chạy vẫn chạy bình thường.</p>
        <Field label="Thông báo" hint={`${m.message.length}/300`}><textarea rows={2} maxLength={300} value={m.message} onChange={e => setM({ ...m, message: e.target.value })} /></Field>
        <Field label="Dự kiến xong (tuỳ chọn)"><input type="datetime-local" value={toLocal(m.until)} onChange={e => setM({ ...m, until: e.target.value ? Math.floor(new Date(e.target.value).getTime() / 1000) : 0 })} /></Field>
        <div className="row gap-sm wrap">
          {saved.enabled
            ? <Button variant="primary" loading={busy} onClick={() => save({ ...m, enabled: false })}>Tắt bảo trì</Button>
            : <Button variant="danger" icon={Wrench} loading={busy} onClick={() => setConfirm(true)}>Bật bảo trì</Button>}
          {dirty && <Button loading={busy} onClick={() => save({ ...m, enabled: saved.enabled })}>Lưu thông báo</Button>}
          <Badge color={saved.enabled ? 'warn' : 'success'}>{saved.enabled ? 'Đang bảo trì' : 'Hoạt động bình thường'}</Badge>
        </div>
      </Card>
      <div className="preview-col"><small className="muted">Xem trước</small><MaintenanceBar m={{ ...m, enabled: true }} /></div>
      {confirm && <ConfirmDialog title="Bật chế độ bảo trì?" danger confirmLabel="Bật bảo trì" onClose={() => setConfirm(false)} onConfirm={() => save({ ...m, enabled: true })}>
        <p className="muted">Người dùng sẽ thấy thông báo bảo trì ngay và không thể thuê tab mới cho đến khi bạn tắt.</p></ConfirmDialog>}
    </div>
  );
}

// KPI helpers for the dashboard.
export function useGrowthKpis() {
  const [k, setK] = useState({ tickets: null, coupons: null });
  useEffect(() => {
    Promise.all([api('/admin/growth').catch(() => null), api('/admin/coupons').catch(() => null)]).then(([g, c]) => {
      const now = Date.now() / 1000;
      setK({ tickets: g?.open_tickets ?? 0, coupons: (c?.coupons || []).filter(x => x.active && (!x.expires || x.expires > now) && (!x.max_uses || x.used < x.max_uses)).length });
    });
  }, []);
  return k;
}
