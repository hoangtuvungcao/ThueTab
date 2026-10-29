import React, { useEffect, useRef, useState } from 'react';
import { ArrowLeft, Send, Plus, MessageCircle, CheckCircle2, Headset } from 'lucide-react';
import { api, ago, dateTime } from '../api.js';
import { POLL } from '../tokens.js';
import { useApp } from '../store.js';
import { usePoll } from '../hooks.js';
import { Button, Card, Empty, PageHead, Badge, Field, Skeleton, ErrorBox, Modal, useToast } from '../components/ui.jsx';

export const TICKET_STATUS = { open: ['Đang chờ', 'warn'], answered: ['Đã trả lời', 'success'], closed: ['Đã đóng', 'dim'] };
export const TicketBadge = ({ s }) => { const [l, c] = TICKET_STATUS[s] || [s, 'dim']; return <Badge color={c}>{l}</Badge>; };

// Chat-style thread. `staff` = viewing as an administrator (their messages sit on the right).
export function TicketThread({ id, staff, onBack, onChange }) {
  const toast = useToast();
  const [t, setT] = useState(null);
  const [err, setErr] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState('');
  const end = useRef(null);
  const load = () => api('/tickets/' + id).then(x => { setT(x); setErr(''); }).catch(e => setErr(e.message));
  useEffect(() => { setT(null); load(); }, [id]);
  usePoll(load, POLL.data);
  useEffect(() => { end.current?.scrollIntoView({ block: 'nearest' }); }, [t?.messages?.length]);
  const send = async e => {
    e.preventDefault();
    if (!body.trim()) return;
    setBusy('send');
    try { await api(`/tickets/${id}/messages`, 'POST', { body: body.trim() }); setBody(''); await load(); onChange?.(); }
    catch (e2) { toast(e2.message, 'error'); }
    setBusy('');
  };
  const close = async () => {
    setBusy('close');
    try { await api(`/tickets/${id}/close`, 'POST'); toast('Đã đóng yêu cầu hỗ trợ.', 'success'); await load(); onChange?.(); }
    catch (e2) { toast(e2.message, 'error'); }
    setBusy('');
  };
  if (err) return <ErrorBox onRetry={load}>{err}</ErrorBox>;
  if (!t) return <Skeleton variant="rows" count={3} />;
  return (
    <Card className="thread" pad={false}>
      <header className="thread-head">
        {onBack && <Button variant="ghost" icon={ArrowLeft} aria-label="Quay lại danh sách" onClick={onBack} />}
        <div className="min0 grow">
          <h2 className="ellipsis" title={t.subject}>{t.subject}</h2>
          <small className="muted">#{t.id.slice(0, 6)} · tạo {dateTime(t.created)}{t.email ? ` · ${t.email}` : ''}</small>
        </div>
        <TicketBadge s={t.status} />
        {t.status !== 'closed' && <Button size="sm" icon={CheckCircle2} loading={busy === 'close'} onClick={close}>Đóng</Button>}
      </header>
      <ol className="messages" aria-label="Các tin nhắn">
        {t.messages.map(m => {
          const mine = staff ? m.staff : !m.staff;
          return (
            <li key={m.id} className={'msg' + (mine ? ' mine' : '') + (m.staff ? ' staff' : '')}>
              <span className="msg-who">{m.staff ? <><Headset size={14} aria-hidden /> Hỗ trợ ThuêTab</> : staff ? (t.email || 'Người dùng') : 'Bạn'}</span>
              <div className="msg-body">{m.body}</div>
              <small className="dim num" title={dateTime(m.created)}>{ago(m.created)}</small>
            </li>
          );
        })}
        <li ref={end} aria-hidden className="msg-end" />
      </ol>
      {t.status === 'closed' ? <p className="thread-closed muted">Yêu cầu đã đóng. Gửi tin nhắn mới để mở lại.</p> : null}
      <form className="reply" onSubmit={send}>
        <textarea rows={2} value={body} maxLength={4000} placeholder={staff ? 'Trả lời người dùng…' : 'Nhập tin nhắn…'} aria-label="Tin nhắn"
          onChange={e => setBody(e.target.value)} onKeyDown={e => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) send(e); }} />
        <Button type="submit" variant="primary" icon={Send} loading={busy === 'send'} disabled={!body.trim()}>Gửi</Button>
      </form>
    </Card>
  );
}

function NewTicket({ onClose, onDone }) {
  const toast = useToast();
  const [f, setF] = useState({ subject: '', body: '' });
  const [busy, setBusy] = useState(false);
  const valid = f.subject.trim().length >= 3 && f.subject.length <= 120 && f.body.trim() && f.body.length <= 4000;
  const submit = async e => {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    try { const t = await api('/tickets', 'POST', { subject: f.subject.trim(), body: f.body.trim() }); toast('Đã gửi yêu cầu. Chúng tôi sẽ phản hồi sớm.', 'success'); onDone(t); }
    catch (e2) { toast(e2.message, 'error'); }
    setBusy(false);
  };
  return (
    <Modal title="Tạo yêu cầu hỗ trợ" desc="Mô tả vấn đề càng chi tiết càng tốt (tên tab, thời điểm, thông báo lỗi)." onClose={onClose}
      footer={<><Button variant="ghost" onClick={onClose}>Hủy</Button><Button variant="primary" type="submit" form="new-ticket" icon={Send} loading={busy} disabled={!valid}>Gửi yêu cầu</Button></>}>
      <form id="new-ticket" className="stack" onSubmit={submit}>
        <Field label="Tiêu đề" hint={`${f.subject.length}/120 · ít nhất 3 ký tự`}><input value={f.subject} maxLength={120} onChange={e => setF({ ...f, subject: e.target.value })} data-autofocus /></Field>
        <Field label="Nội dung" hint={`${f.body.length}/4000`}><textarea rows={6} value={f.body} maxLength={4000} onChange={e => setF({ ...f, body: e.target.value })} /></Field>
      </form>
    </Modal>
  );
}

export default function Support() {
  const { param, go, loadNotes } = useApp();
  const [list, setList] = useState(null);
  const [creating, setCreating] = useState(false);
  const load = () => api('/tickets').then(setList).catch(() => setList([]));
  useEffect(() => { load(); }, [param]);
  if (param) return (
    <>
      <PageHead title="Hỗ trợ" />
      <TicketThread id={param} onBack={() => go('support')} onChange={() => { load(); loadNotes(); }} />
    </>
  );
  return (
    <>
      <PageHead title="Hỗ trợ" desc="Gửi yêu cầu và trao đổi trực tiếp với đội ngũ ThuêTab.">
        <Button variant="primary" icon={Plus} onClick={() => setCreating(true)}>Tạo yêu cầu</Button>
      </PageHead>
      {!list ? <Skeleton variant="rows" count={3} /> : list.length === 0 ? (
        <Empty icon={MessageCircle} title="Chưa có yêu cầu hỗ trợ" action={<Button variant="primary" icon={Plus} onClick={() => setCreating(true)}>Tạo yêu cầu</Button>}>
          Gặp sự cố với tab, game hay thanh toán? Gửi yêu cầu, chúng tôi sẽ trả lời ngay tại đây và báo cho bạn qua chuông thông báo.
        </Empty>
      ) : (
        <Card pad={false}>
          <ul className="ticket-list">
            {list.map(t => (
              <li key={t.id}>
                <button type="button" onClick={() => go('support/' + t.id)}>
                  <span className="min0 grow"><strong className="ellipsis" title={t.subject}>{t.subject}</strong>
                    <small className="muted num">#{t.id.slice(0, 6)} · {t.messages_count} tin nhắn · cập nhật {ago(t.updated)}</small></span>
                  <TicketBadge s={t.status} />
                </button>
              </li>
            ))}
          </ul>
        </Card>
      )}
      {creating && <NewTicket onClose={() => setCreating(false)} onDone={t => { setCreating(false); go('support/' + t.id); }} />}
    </>
  );
}
