import React, { useEffect, useState } from 'react';
import { Save, KeyRound, LogOut, Eye, EyeOff, Smartphone, Monitor } from 'lucide-react';
import { api, dateTime, money } from '../api.js';
import { useApp } from '../store.js';
import { Button, Card, Field, PageHead, Alert, Modal, Badge, Skeleton, useToast, describeAgent, Confirm } from '../components/ui.jsx';

// Signed-in devices (GET /me/sessions) with "Đăng xuất thiết bị này".
function Sessions() {
  const toast = useToast();
  const [list, setList] = useState(null);
  const [busy, setBusy] = useState('');
  const load = () => api('/me/sessions').then(setList).catch(() => setList([]));
  useEffect(() => { load(); }, []);
  const kick = async id => {
    setBusy(id);
    try { await api('/me/sessions/' + id, 'DELETE'); toast('Đã đăng xuất thiết bị.', 'success'); await load(); }
    catch (e) { toast(e.message, 'error'); }
    setBusy('');
  };
  const icon = a => (/Android|iPhone|iPad|Mobile/i.test(a) ? Smartphone : Monitor);
  return (
    <Card title="Thiết bị đăng nhập" pad={false}>
      {!list ? <div className="card-pad"><Skeleton variant="rows" count={2} /></div> : (
        <ul className="drawer-list pad-list">
          {list.map(x => {
            const I = icon(x.agent);
            return (
              <li key={x.id}>
                <span className="dl-icon"><I size={18} aria-hidden /></span>
                <div className="min0 grow">
                  <span className="row gap-sm min0"><strong className="ellipsis" title={x.agent}>{describeAgent(x.agent)}</strong>{x.current && <Badge color="success">Thiết bị này</Badge>}</span>
                  <small className="muted num">Đăng nhập {dateTime(x.created)} · hết hạn {dateTime(x.expires)}</small>
                </div>
                {!x.current && <Button size="sm" variant="danger-ghost" icon={LogOut} loading={busy === x.id} onClick={() => kick(x.id)}>Đăng xuất thiết bị này</Button>}
              </li>
            );
          })}
        </ul>
      )}
    </Card>
  );
}

export default function Account() {
  const { user, act, logoutAll } = useApp();
  const toast = useToast();
  const [name, setName] = useState(user.name);
  const [pw, setPw] = useState({ old: '', new: '', confirm: '' });
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState('');
  const [err, setErr] = useState('');
  const [confirmAll, setConfirmAll] = useState(false);

  const saveName = async e => {
    e.preventDefault();
    setBusy('name');
    await act(() => api('/me', 'PATCH', { name: name.trim() }), 'Đã lưu tên hiển thị.');
    setBusy('');
  };
  const changePw = async e => {
    e.preventDefault();
    setErr('');
    if (pw.new.length < 10) return setErr('Mật khẩu mới cần ít nhất 10 ký tự.');
    if (pw.new !== pw.confirm) return setErr('Mật khẩu nhập lại không khớp.');
    setBusy('pw');
    try {
      await api('/me/password', 'POST', { old: pw.old, new: pw.new });
      setPw({ old: '', new: '', confirm: '' });
      toast('Đã đổi mật khẩu. Các thiết bị khác đã bị đăng xuất.', 'success');
    } catch (e2) { setErr(e2.message); }
    setBusy('');
  };
  const type = show ? 'text' : 'password';

  return (
    <>
      <PageHead title="Tài khoản" desc="Thông tin cá nhân, mật khẩu và phiên đăng nhập." />
      <div className="two-col">
        <Card title="Hồ sơ">
          <form className="stack" onSubmit={saveName}>
            <Field label="Email"><input value={user.email} readOnly disabled /></Field>
            <Field label="Tên hiển thị"><input value={name} maxLength={60} onChange={e => setName(e.target.value)} autoComplete="nickname" /></Field>
            <dl className="kv">
              <div><dt>Ngày tạo</dt><dd>{dateTime(user.created)}</dd></div>
              <div><dt>Số dư</dt><dd>{money(user.balance)}</dd></div>
              <div><dt>Dùng thử</dt><dd>{user.trial_used ? 'Đã dùng' : user.trial_approved ? 'Được dùng' : 'Chưa được duyệt'}</dd></div>
            </dl>
            <div><Button variant="primary" type="submit" icon={Save} loading={busy === 'name'} disabled={!name.trim() || name.trim() === user.name}>Lưu</Button></div>
          </form>
        </Card>
        <Card title="Đổi mật khẩu">
          <form className="stack" onSubmit={changePw}>
            {err && <Alert kind="danger">{err}</Alert>}
            <input type="text" name="username" value={user.email} autoComplete="username" readOnly hidden />
            <Field label="Mật khẩu hiện tại"><input type={type} value={pw.old} onChange={e => setPw({ ...pw, old: e.target.value })} autoComplete="current-password" required /></Field>
            <Field label="Mật khẩu mới" hint="Ít nhất 10 ký tự."><input type={type} value={pw.new} onChange={e => setPw({ ...pw, new: e.target.value })} autoComplete="new-password" required /></Field>
            <Field label="Nhập lại mật khẩu mới"><input type={type} value={pw.confirm} onChange={e => setPw({ ...pw, confirm: e.target.value })} autoComplete="new-password" required /></Field>
            <div className="row gap-sm wrap">
              <Button variant="primary" type="submit" icon={KeyRound} loading={busy === 'pw'} disabled={!pw.old || !pw.new}>Đổi mật khẩu</Button>
              <Button variant="ghost" icon={show ? EyeOff : Eye} onClick={() => setShow(!show)}>{show ? 'Ẩn' : 'Hiện'} mật khẩu</Button>
            </div>
          </form>
        </Card>
      </div>
      <Sessions />
      <Card title="Phiên đăng nhập">
        <div className="row gap-md wrap between">
          <p className="muted grow">Đăng xuất khỏi mọi trình duyệt và ứng dụng đang đăng nhập tài khoản này, kể cả thiết bị hiện tại.</p>
          <Button variant="danger-ghost" icon={LogOut} onClick={() => setConfirmAll(true)}>Đăng xuất mọi thiết bị</Button>
        </div>
      </Card>
      {confirmAll && (
        <Confirm title="Đăng xuất mọi thiết bị?" danger icon={LogOut} confirmLabel="Đăng xuất tất cả" onClose={() => setConfirmAll(false)} onConfirm={logoutAll}>
          Tab của bạn vẫn tiếp tục chạy. Bạn cần đăng nhập lại trên từng thiết bị.
        </Confirm>
      )}
    </>
  );
}
