import React, { useState } from 'react';
import { Eye, EyeOff, Gift } from 'lucide-react';
import { hashQuery } from '../hooks.js';
import { api } from '../api.js';
import { useApp } from '../store.js';
import { Modal, Button, Field, Alert, Segmented } from '../components/ui.jsx';

export default function AuthDialog({ mode: initial, onClose }) {
  const { onLogin } = useApp();
  const [mode, setMode] = useState(initial);
  const ref = (hashQuery().ref || '').toUpperCase().slice(0, 16);
  const [f, setF] = useState({ email: '', password: '', name: '' });
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const set = k => e => setF({ ...f, [k]: e.target.value });

  const login = async creds => {
    setBusy(true);
    setErr('');
    try {
      if (mode === 'register' && creds === f) await api('/auth/register', 'POST', { email: f.email.trim(), password: f.password, name: f.name.trim() || 'Game thủ', ref: ref || undefined });
      const r = await api('/auth/login', 'POST', { email: creds.email.trim(), password: creds.password });
      onLogin(r.user);
    } catch (e) {
      setErr(e.message);
      setBusy(false);
    }
  };
  const submit = e => {
    e.preventDefault();
    if (f.password.length < 10) return setErr('Mật khẩu cần ít nhất 10 ký tự.');
    login(f);
  };

  return (
    <Modal title={mode === 'login' ? 'Đăng nhập' : 'Tạo tài khoản'} desc="Quản lý tab treo game của bạn trên mọi thiết bị." onClose={onClose}>
      <form className="stack" onSubmit={submit} noValidate>
        <Segmented label="Chế độ" value={mode} onChange={m => { setMode(m); setErr(''); }} options={[['login', 'Đăng nhập'], ['register', 'Đăng ký']]} />
        {err && <Alert kind="danger">{err}</Alert>}
        {mode === 'register' && ref && <Alert kind="info" icon={Gift}>Bạn được giới thiệu bởi mã <b className="mono">{ref}</b>.</Alert>}
        {mode === 'register' && <Field label="Tên hiển thị"><input name="name" value={f.name} onChange={set('name')} maxLength={60} autoComplete="nickname" placeholder="Game thủ" /></Field>}
        <Field label="Email"><input name="email" type="email" value={f.email} onChange={set('email')} autoComplete="email" required data-autofocus /></Field>
        <div className="field">
          <label htmlFor="pw">Mật khẩu</label>
          <div className="input-addon">
            <input id="pw" name="password" type={show ? 'text' : 'password'} value={f.password} onChange={set('password')} minLength={10} required
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'} />
            <button type="button" className="btn btn-ghost btn-icon" onClick={() => setShow(!show)} aria-label={show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}>
              {show ? <EyeOff size={16} /> : <Eye size={16} />}
            </button>
          </div>
          {mode === 'register' && <small className="hint">Ít nhất 10 ký tự.</small>}
        </div>
        <Button variant="primary" type="submit" loading={busy} className="block">{mode === 'login' ? 'Đăng nhập' : 'Tạo tài khoản'}</Button>
      </form>
    </Modal>
  );
}
