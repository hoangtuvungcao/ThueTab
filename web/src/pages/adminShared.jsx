import React, { useState } from 'react';
import { Pause, Play, Repeat, RotateCw, Clock, Terminal, Trash2, MonitorPlay } from 'lucide-react';
import { api, money, dateTime, serverNow } from '../api.js';
import { tabState } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Modal, Field, Menu, Alert, Confirm } from '../components/ui.jsx';

// Calls an admin endpoint through act() (toast + refresh) and also refreshes admin data.
export function useAdminRun(after) {
  const { act, refreshAdmin } = useApp();
  return async (fn, msg) => { const r = await act(fn, msg); await refreshAdmin(); after?.(); return r; };
}

// Generic confirmation (centred Confirm layout). With `requireText`, confirming unlocks only after typing it exactly.
export function ConfirmDialog({ title, children, confirmLabel, danger, requireText, onConfirm, onClose, extra }) {
  const [typed, setTyped] = useState('');
  const ok = !requireText || typed.trim().toLowerCase() === requireText.toLowerCase();
  return (
    <Confirm title={title} danger={danger} confirmLabel={confirmLabel} onClose={onClose} disabled={!ok} onConfirm={onConfirm}
      extra={<>{extra}{requireText && <Field label={`Nhập "${requireText}" để xác nhận`}><input value={typed} onChange={e => setTyped(e.target.value)} autoComplete="off" data-autofocus /></Field>}</>}>
      {children}
    </Confirm>
  );
}

// Balance adjustment, gift hours (one or many tabs), manual order confirmation.
export function AdminForm({ form, email, run, onClose }) {
  const [a, setA] = useState(form.kind === 'extend' ? '24' : '');
  const [b, setB] = useState('');
  const [busy, setBusy] = useState(false);
  const t = form.target;
  const many = Array.isArray(t);
  const cfg = {
    balance: {
      title: `Điều chỉnh số dư · ${t.email}`, desc: `Số dư hiện tại: ${money(t.balance)}. Nhập số âm để trừ.`,
      valid: /^-?\d+$/.test(a) && +a !== 0 && Math.abs(+a) <= 5000000 && b.trim().length >= 3,
      call: () => api(`/admin/users/${t.id}/balance`, 'POST', { amount: +a, reason: b.trim() }), ok: 'Đã điều chỉnh số dư.',
      fields: <>
        <Field label="Số tiền (VNĐ, ±)" hint="Tối đa ±5.000.000đ mỗi lần."><input inputMode="numeric" value={a} onChange={e => setA(e.target.value.replace(/[^\d-]/g, ''))} placeholder="50000 hoặc -20000" data-autofocus /></Field>
        <Field label="Lý do" hint="3–120 ký tự, hiện trong lịch sử ví của người dùng."><input value={b} maxLength={120} onChange={e => setB(e.target.value)} placeholder="Bù lỗi, khuyến mãi…" /></Field>
      </>
    },
    extend: {
      title: many ? `Tặng giờ cho ${t.length} tab` : `Tặng giờ · ${t.name}`,
      desc: many ? 'Áp dụng cho từng tab đã chọn.' : `Chủ tab: ${email[t.user_id] || '—'}. Hạn hiện tại: ${dateTime(t.expires)}.`,
      valid: /^\d+$/.test(a) && +a >= 1 && +a <= 2160,
      call: async () => { for (const x of many ? t : [t]) await api(`/admin/tabs/${x.id}/extend`, 'POST', { hours: +a }); }, ok: `Đã tặng ${a} giờ.`,
      fields: <>
        <div className="chips wrap">{[1, 6, 24, 72, 168].map(h => <button key={h} type="button" className={'chip' + (a === String(h) ? ' on' : '')} onClick={() => setA(String(h))}>{h < 24 ? `${h} giờ` : `${h / 24} ngày`}</button>)}</div>
        <Field label="Số giờ" hint="Từ 1 đến 2160 giờ (90 ngày)."><input inputMode="numeric" value={a} onChange={e => setA(e.target.value.replace(/\D/g, ''))} /></Field>
      </>
    },
    confirm: {
      title: `Xác nhận tay đơn ${t.code}`, desc: `${money(t.amount)} cho ${email[t.user_id] || '—'}. Chỉ dùng khi đã thấy tiền vào tài khoản ngân hàng.`,
      valid: b.trim().length >= 3,
      call: () => api(`/admin/orders/${t.id}/confirm`, 'POST', { reference: b.trim() }), ok: `Đã cộng ${money(t.amount)}.`,
      fields: <Field label="Mã giao dịch ngân hàng" hint="Dùng để tránh cộng trùng một giao dịch."><input value={b} maxLength={100} onChange={e => setB(e.target.value)} data-autofocus /></Field>
    }
  }[form.kind];
  const submit = async e => {
    e.preventDefault();
    if (!cfg.valid) return;
    setBusy(true);
    const ok = await run(cfg.call, cfg.ok);
    setBusy(false);
    if (ok) onClose();
  };
  return (
    <Modal title={cfg.title} desc={cfg.desc} onClose={onClose}
      footer={<><Button variant="ghost" onClick={onClose}>Hủy</Button><Button variant="primary" type="submit" form="admin-form" loading={busy} disabled={!cfg.valid}>Xác nhận</Button></>}>
      <form id="admin-form" className="stack" onSubmit={submit}>{cfg.fields}</form>
    </Modal>
  );
}

// Force-delete a tab, optionally keeping its paid slot for the user.
export function DeleteTabDialog({ tab, run, onClose }) {
  const [keep, setKeep] = useState(true);
  return (
    <ConfirmDialog title={`Xoá cưỡng chế tab "${tab.name}"?`} danger confirmLabel="Xoá tab" onClose={onClose}
      onConfirm={() => run(() => api(`/admin/tabs/${tab.id}?release_slot=${!keep}`, 'DELETE'), 'Đã xoá tab.')}
      extra={<label className="check"><input type="checkbox" checked={keep} onChange={e => setKeep(e.target.checked)} /> Giữ slot cho người dùng (thời hạn đã trả tiền)</label>}>
      <p className="muted">Game trong tab sẽ dừng ngay và tab bị xoá khỏi tài khoản người dùng.</p>
    </ConfirmDialog>
  );
}

// Row menu for a tab in admin lists. `ownerJars` lets the game picker show the owner's files.
export function AdminTabMenu({ t, run, ownerJars, onExtend, onDelete }) {
  const { open } = useApp();
  const state = tabState(t, serverNow());
  const live = t.desired === 'running' && t.expires > serverNow();
  return (
    <Menu label={`Thao tác cho ${t.name}`} items={[
      live ? { label: 'Dừng', icon: Pause, onClick: () => run(() => api('/tabs/' + t.id, 'PATCH', { desired: 'stopped' }), `Đã dừng "${t.name}".`) }
        : t.game && state !== 'expired' && { label: 'Bật', icon: Play, onClick: () => run(() => api('/tabs/' + t.id, 'PATCH', { desired: 'running' }), `Đang bật "${t.name}".`) },
      { label: 'Xem màn hình', icon: MonitorPlay, disabled: !live, hint: live ? undefined : 'Tab không chạy', onClick: () => open('viewer', { tab: t }) },
      { label: 'Đổi game', icon: Repeat, onClick: () => open('game', { tab: t, ownerJars }) },
      { label: 'Kích thước màn hình', icon: RotateCw, onClick: () => open('screen', { tab: t }) },
      { label: 'Tặng giờ', icon: Clock, onClick: onExtend },
      { label: 'Xem nhật ký', icon: Terminal, onClick: () => open('logs', { tab: t }) },
      { label: 'Xoá cưỡng chế', icon: Trash2, danger: true, onClick: onDelete }
    ]} />
  );
}

export const CSV = ['users', 'orders', 'ledger', 'tabs'];
export const CSV_LABEL = { users: 'Người dùng', orders: 'Đơn nạp', ledger: 'Lịch sử ví', tabs: 'Tab' };
// Authenticated: fetched with downloadApi (works with cookie or Bearer token).
export const csvPath = k => `/admin/export/${k}.csv`;
export { Alert };
