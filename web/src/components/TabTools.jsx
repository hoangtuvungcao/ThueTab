import React, { Suspense, lazy, useEffect, useState } from 'react';
import { Clock, FolderOpen, Share2, Link2, Trash2, Eye, Gamepad2, Plus, QrCode as QrIcon } from 'lucide-react';
// Loaded only when a share dialog opens (keeps the QR encoder out of the main bundle).
const QrCode = lazy(() => import('./QrCode.jsx'));
import { api, dateTime, remaining } from '../api.js';
import { useApp } from '../store.js';
import { Modal, Button, Field, Segmented, Switch, Empty, Spinner, CopyButton, Badge, useToast } from './ui.jsx';

// Existing group names of the user's tabs, for suggestions.
export const groupsOf = tabs => [...new Set((tabs || []).map(t => t.group).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'vi'));

// Group + daily restart time (PATCH /tabs/{id}/schedule).
export function ScheduleDialog({ tab }) {
  const { tabs, act, close } = useApp();
  const [group, setGroup] = useState(tab.group || '');
  const [on, setOn] = useState(!!tab.restart_at);
  const [time, setTime] = useState(tab.restart_at || '04:00');
  const [busy, setBusy] = useState(false);
  const valid = group.length <= 40 && (!on || /^([01]\d|2[0-3]):[0-5]\d$/.test(time));
  const submit = async e => {
    e.preventDefault();
    setBusy(true);
    const ok = await act(() => api(`/tabs/${tab.id}/schedule`, 'PATCH', { group: group.trim(), restart_at: on ? time : '' }), 'Đã lưu nhóm và lịch khởi động lại.');
    setBusy(false);
    if (ok) close();
  };
  return (
    <Modal title={`Nhóm & hẹn giờ · ${tab.name}`} desc="Nhóm giúp lọc và điều khiển nhiều tab một lúc. Hẹn giờ khởi động lại game mỗi ngày để giải phóng bộ nhớ." onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" type="submit" form="schedule" loading={busy} disabled={!valid}>Lưu</Button></>}>
      <form id="schedule" className="stack" onSubmit={submit}>
        <Field label="Nhóm" hint="Để trống nếu không xếp nhóm. Tối đa 40 ký tự.">
          <input value={group} maxLength={40} list="tab-groups" placeholder="Ví dụ: Nhân vật chính" onChange={e => setGroup(e.target.value)} data-autofocus />
        </Field>
        <datalist id="tab-groups">{groupsOf(tabs).map(g => <option key={g} value={g} />)}</datalist>
        <Switch label="Tự khởi động lại mỗi ngày" desc="Game được bật lại vào giờ đã chọn (giờ Việt Nam)." checked={on} onChange={setOn} />
        {on && <Field label="Giờ khởi động lại"><input type="time" value={time} onChange={e => setTime(e.target.value)} required /></Field>}
      </form>
    </Modal>
  );
}

// Assign a group to several tabs at once (POST /tabs/batch action=group).
export function GroupDialog({ ids, onDone }) {
  const { tabs, act, close } = useApp();
  const [group, setGroup] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async e => {
    e.preventDefault();
    setBusy(true);
    const ok = await act(() => api('/tabs/batch', 'POST', { ids, action: 'group', group: group.trim() }), group.trim() ? `Đã xếp ${ids.length} tab vào nhóm "${group.trim()}".` : `Đã bỏ nhóm của ${ids.length} tab.`);
    setBusy(false);
    if (ok) { onDone?.(); close(); }
  };
  return (
    <Modal title={`Gán nhóm cho ${ids.length} tab`} onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" type="submit" form="group-form" loading={busy}>Lưu</Button></>}>
      <form id="group-form" className="stack" onSubmit={submit}>
        <Field label="Tên nhóm" hint="Để trống để bỏ nhóm."><input value={group} maxLength={40} list="tab-groups-b" onChange={e => setGroup(e.target.value)} data-autofocus /></Field>
        <datalist id="tab-groups-b">{groupsOf(tabs).map(g => <option key={g} value={g} />)}</datalist>
      </form>
    </Modal>
  );
}

const DURATIONS = [[1, '1 giờ'], [24, '24 giờ'], [168, '7 ngày'], [720, '30 ngày']];

// Share links for a tab: create (view only / control, duration, label), list with copy + revoke.
export function ShareDialog({ tab }) {
  const { close } = useApp();
  const toast = useToast();
  const [list, setList] = useState(null);
  const [f, setF] = useState({ can_control: false, hours: 24, label: '' });
  const [busy, setBusy] = useState('');
  const [qrFor, setQrFor] = useState(null); // token whose QR is shown (default: newest link)
  const load = () => api(`/tabs/${tab.id}/shares`).then(setList).catch(e => { toast(e.message, 'error'); setList([]); });
  useEffect(() => { load(); }, [tab.id]);
  const url = p => location.origin + (p.startsWith('/') ? p : '/' + p);
  const shown = list?.find(x => x.token === qrFor) || list?.[0];
  const create = async e => {
    e.preventDefault();
    setBusy('create');
    try { const x = await api(`/tabs/${tab.id}/shares`, 'POST', { ...f, label: f.label.trim() }); toast('Đã tạo link chia sẻ.', 'success'); setF({ ...f, label: '' }); await load(); navigator.clipboard?.writeText(url(x.path)).catch(() => {}); }
    catch (e2) { toast(e2.message, 'error'); }
    setBusy('');
  };
  const revoke = async token => {
    setBusy(token);
    try { await api(`/tabs/${tab.id}/shares/${token}`, 'DELETE'); toast('Đã thu hồi link.', 'success'); await load(); }
    catch (e2) { toast(e2.message, 'error'); }
    setBusy('');
  };
  return (
    <Modal wide title={`Chia sẻ · ${tab.name}`} desc="Người có link xem màn hình game mà không cần đăng nhập. Chỉ bật điều khiển cho người bạn tin tưởng." onClose={close}
      footer={<Button variant="ghost" onClick={close}>Đóng</Button>}>
      <div className="stack">
        <form className="share-form" onSubmit={create}>
          <Segmented label="Quyền" value={f.can_control ? 'ctl' : 'view'} onChange={v => setF({ ...f, can_control: v === 'ctl' })}
            options={[['view', 'Chỉ xem'], ['ctl', 'Cho điều khiển']]} />
          <Segmented label="Thời hạn" value={f.hours} onChange={v => setF({ ...f, hours: v })} options={DURATIONS} />
          <div className="row gap-sm">
            <input value={f.label} maxLength={40} placeholder="Ghi chú (tuỳ chọn), ví dụ: cho Minh" aria-label="Ghi chú link" onChange={e => setF({ ...f, label: e.target.value })} />
            <Button type="submit" variant="primary" icon={Plus} loading={busy === 'create'} disabled={(list?.length || 0) >= 10}>Tạo link</Button>
          </div>
        </form>
        {!list ? <Spinner /> : list.length === 0 ? <Empty icon={Link2} title="Chưa có link nào">Tạo link để cho bạn bè xem game của bạn.</Empty> : (
          <ul className="share-list">
            {list.map(x => (
              <li key={x.token}>
                <span className="share-kind">{x.can_control ? <Badge color="success"><Gamepad2 size={12} aria-hidden /> Điều khiển</Badge> : <Badge color="info"><Eye size={12} aria-hidden /> Chỉ xem</Badge>}</span>
                <div className="min0 grow">
                  <span className="ellipsis mono small" title={url(x.path)}>{url(x.path)}</span>
                  <small className="muted num" title={dateTime(x.expires)}>{x.label ? x.label + ' · ' : ''}{remaining(x.expires)}</small>
                </div>
                <Button size="sm" variant={shown?.token === x.token ? 'secondary' : 'ghost'} icon={QrIcon} aria-label="Hiện mã QR" aria-pressed={shown?.token === x.token} onClick={() => setQrFor(x.token)} />
                <CopyButton value={url(x.path)} label="Sao chép link" />
                {navigator.share && <Button size="sm" variant="ghost" icon={Share2} aria-label="Chia sẻ link" onClick={() => navigator.share({ title: tab.name, url: url(x.path) }).catch(() => {})} />}
                <Button size="sm" variant="ghost" icon={Trash2} aria-label="Thu hồi link" loading={busy === x.token} onClick={() => revoke(x.token)} />
              </li>
            ))}
          </ul>
        )}
        {shown && (
          <div className="share-qr">
            <Suspense fallback={<Spinner label="" />}><QrCode value={url(shown.path)} name={`thuetab-${tab.name.replace(/\s+/g, '_')}`} /></Suspense>
            <div className="min0">
              <strong>{shown.can_control ? 'Link cho điều khiển' : 'Link chỉ xem'}{shown.label ? ` · ${shown.label}` : ''}</strong>
              <p className="muted small">Người nhận quét mã để mở màn hình game ngay trên điện thoại, không cần cài đặt hay đăng nhập.</p>
            </div>
          </div>
        )}
        <small className="muted">Tối đa 10 link mỗi tab. Thu hồi link sẽ ngắt người đang xem ngay lập tức.</small>
      </div>
    </Modal>
  );
}
