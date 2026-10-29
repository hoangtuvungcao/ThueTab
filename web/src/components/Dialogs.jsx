import React, { useEffect, useState } from 'react';
import { RefreshCw, Gift, Layers, CreditCard, Minus, Plus, Repeat } from 'lucide-react';
import { api, money, remaining, serverNow, dateTime } from '../api.js';
import { POLL } from '../tokens.js';
import { useApp } from '../store.js';
import { Modal, Button, Field, Alert, Empty, Spinner, CouponField, MAINT_HINT, Confirm } from './ui.jsx';
import Viewer from './Viewer.jsx';
import GamePicker, { CUSTOM, sameChoice } from './GamePicker.jsx';
import { ScreenPicker, ScreenDialog } from './ScreenPicker.jsx';
import { ScheduleDialog, ShareDialog, GroupDialog } from './TabTools.jsx';

const perDay = p => money(Math.round(p.price / p.days)) + '/ngày';

export function PlanPicker({ value, onChange }) {
  const { config } = useApp();
  return (
    <div className="choice-grid" role="radiogroup" aria-label="Gói thuê">
      {config.plans.map(p => (
        <button key={p.id} type="button" role="radio" aria-checked={value === p.id} className={'choice' + (value === p.id ? ' on' : '')} onClick={() => onChange(p.id)}>
          <strong>{p.days} ngày</strong>
          <span className="choice-price">{money(p.price)}</span>
          <small>{perDay(p)}</small>
        </button>
      ))}
    </div>
  );
}

function CostRow({ cost, balance, original }) {
  const { go, close } = useApp();
  const short = cost > balance;
  return (
    <div className="cost">
      <div><span className="muted">Chi phí</span><strong className="num">{original != null && original !== cost && <s className="dim">{money(original)}</s>} {cost ? money(cost) : 'Miễn phí'}</strong></div>
      <div><span className="muted">Số dư sau thanh toán</span><strong style={short ? { color: 'var(--danger)' } : undefined}>{money(balance - cost)}</strong></div>
      {short && <Alert kind="warn">Số dư chưa đủ. <button type="button" className="link" onClick={() => { close(); go('wallet'); }}>Nạp thêm vào ví</button></Alert>}
    </div>
  );
}

export const slotLabel = (slots, s) => `Slot ${slots.filter(x => x.expires > serverNow()).findIndex(x => x.id === s.id) + 1}`;

function RentDialog({ game: presetGame, plan: presetPlan, slotId: presetSlot, jarId: presetJar }) {
  const { config, user, tabs, slots, jars, act, close, prefs, maint } = useApp();
  const now = serverNow();
  const [screen, setScreen] = useState(config.screens.some(s => s.id === prefs.default_screen) ? prefs.default_screen : config.screens[0]?.id);
  const freeSlots = slots.filter(s => !s.tab_id && s.expires > now);
  const trialOk = user.trial_approved && !user.trial_used;
  const firstJar = jars.find(j => j.status === 'approved')?.id;
  const [choice, setChoice] = useState(presetJar ? { game: CUSTOM, jar: presetJar }
    : presetGame ? { game: presetGame, jar: null } : firstJar ? { game: CUSTOM, jar: firstJar } : { game: null, jar: null });
  const [mode, setMode] = useState(presetSlot ? 'slot' : 'plan');
  const [plan, setPlan] = useState(presetPlan || 'month');
  const [slotId, setSlot] = useState(presetSlot || freeSlots[0]?.id || '');
  const [name, setName] = useState(`Tab ${(tabs?.length || 0) + 1}`);
  const [busy, setBusy] = useState(false);
  const p = config.plans.find(x => x.id === plan);
  const [coupon, setCoupon] = useState(null);
  const cost = mode === 'plan' ? (coupon ? coupon.final : p.price) : 0;
  const valid = !maint && (choice.game !== CUSTOM || choice.jar) && name.trim() && (mode !== 'slot' || slotId) && cost <= user.balance;

  const submit = async e => {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    const ok = await act(() => api('/tabs', 'POST', {
      name: name.trim(), plan, trial: mode === 'trial', screen, coupon: mode === 'plan' && coupon ? coupon.code : undefined,
      game: choice.game || undefined,
      slot_id: mode === 'slot' ? slotId : undefined,
      custom_jar_id: choice.game === CUSTOM ? choice.jar : undefined
    }), t => (t.game ? `Đã tạo "${t.name}". Game đang khởi động…` : `Đã tạo "${t.name}". Chọn game để bắt đầu chơi.`));
    setBusy(false);
    if (ok) close();
  };

  const sources = [
    ['plan', CreditCard, 'Thuê theo gói', 'Trừ tiền từ ví'],
    freeSlots.length && ['slot', Layers, 'Dùng slot trống', `${freeSlots.length} slot sẵn có · không mất phí`],
    trialOk && ['trial', Gift, `Dùng thử ${config.trial_minutes} phút`, 'Miễn phí · chỉ một lần']
  ].filter(Boolean);

  return (
    <Modal wide title="Thuê tab mới" desc="Mỗi tab là một máy treo riêng chạy game 24/24. Bạn có thể đổi game bất cứ lúc nào." onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" type="submit" form="rent-form" loading={busy} disabled={!valid} title={maint ? MAINT_HINT : undefined}>
        {cost ? `Thuê · ${money(cost)}` : 'Tạo tab'}</Button></>}>
      <form id="rent-form" className="stack" onSubmit={submit}>
        {maint && <Alert kind="warn">{MAINT_HINT}</Alert>}
        <fieldset>
          <legend>Thời hạn</legend>
          {sources.length > 1 && (
            <div className="source-row" role="radiogroup" aria-label="Hình thức">
              {sources.map(([v, I, t, s]) => (
                <button key={v} type="button" role="radio" aria-checked={mode === v} className={'choice choice-row' + (mode === v ? ' on' : '')} onClick={() => setMode(v)}>
                  <I size={18} aria-hidden /><span><strong>{t}</strong><small>{s}</small></span>
                </button>
              ))}
            </div>
          )}
          {mode === 'plan' && <PlanPicker value={plan} onChange={setPlan} />}
          {mode === 'slot' && (
            <Field label="Slot trống">
              <select value={slotId} onChange={e => setSlot(e.target.value)}>
                {freeSlots.map(s => <option key={s.id} value={s.id}>{slotLabel(slots, s)} · {remaining(s.expires).toLowerCase()}</option>)}
              </select>
            </Field>
          )}
          {mode === 'trial' && <Alert kind="info">Tab dùng thử chạy {config.trial_minutes} phút rồi tự dừng. Mỗi tài khoản chỉ dùng thử một lần.</Alert>}
        </fieldset>

        <Field label="Tên tab"><input value={name} maxLength={60} onChange={e => setName(e.target.value)} required /></Field>

        <fieldset>
          <legend>Game <span className="dim">· tuỳ chọn</span></legend>
          <GamePicker value={choice} onChange={setChoice} jars={jars} allowNone />
        </fieldset>
        {config.screens?.length > 0 && (
          <fieldset>
            <legend>Màn hình <span className="dim">· cho game J2ME, đổi được sau</span></legend>
            <ScreenPicker screens={config.screens} value={screen} onChange={setScreen} />
          </fieldset>
        )}
        {mode === 'plan' && <CouponField context="rent" amount={p.price} value={coupon} onChange={setCoupon} />}
        <CostRow cost={cost} balance={user.balance} original={mode === 'plan' ? p.price : undefined} />
      </form>
    </Modal>
  );
}

// Switch what a tab runs. Admins switching another user's tab can only pick that user's JARs.
function ChangeGameDialog({ tab, ownerJars }) {
  const { jars, act, close, refreshAdmin, user } = useApp();
  const list = ownerJars || jars;
  const current = { game: tab.game || null, jar: tab.custom_jar_id };
  const [choice, setChoice] = useState(current);
  const [busy, setBusy] = useState(false);
  const changed = !sameChoice(choice, current) && choice.game;
  const running = tab.desired === 'running';
  const submit = async () => {
    setBusy(true);
    const ok = await act(async () => {
      await api('/tabs/' + tab.id, 'PATCH', { game: choice.game, custom_jar_id: choice.game === CUSTOM ? choice.jar : null });
      if (!tab.game && tab.desired !== 'running') await api('/tabs/' + tab.id, 'PATCH', { desired: 'running' }); // first game: start right away
    }, !tab.game ? 'Đã chọn game. Tab đang khởi động…' : running ? 'Đã đổi game. Tab đang khởi động lại…' : 'Đã đổi game. Bật tab để chạy game mới.');
    if (user.role === 'admin') refreshAdmin();
    setBusy(false);
    if (ok) close();
  };
  return (
    <Modal wide title={tab.game ? `Đổi game · ${tab.name}` : `Chọn game · ${tab.name}`} desc={!tab.game ? 'Chọn file .jar để tab bắt đầu chạy. Có thể đổi game bất cứ lúc nào.' : running ? 'Tab sẽ tự khởi động lại với game mới. Thời hạn tab giữ nguyên.' : 'Thời hạn tab giữ nguyên. Bật tab để chạy game mới.'} onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" icon={Repeat} onClick={submit} loading={busy} disabled={!changed}>{!tab.game ? 'Chạy game này' : running ? 'Đổi & khởi động lại' : 'Đổi game'}</Button></>}>
      <GamePicker value={choice} onChange={setChoice} jars={list} current={current} allowUpload={!ownerJars} />
    </Modal>
  );
}

function BuySlotsDialog() {
  const { config, user, status, act, close, maint } = useApp();
  const [qty, setQty] = useState(1);
  const [plan, setPlan] = useState('month');
  const [busy, setBusy] = useState(false);
  const [coupon, setCoupon] = useState(null);
  const p = config.plans.find(x => x.id === plan);
  const full = p.price * qty;
  const cost = coupon ? coupon.final : full;
  const submit = async () => {
    setBusy(true);
    const ok = await act(() => api('/slots', 'POST', { quantity: qty, plan, coupon: coupon?.code }), `Đã mua ${qty} slot.`);
    setBusy(false);
    if (ok) close();
  };
  return (
    <Modal title="Mua slot trống" desc="Slot là chỗ giữ sẵn; bạn gắn tab vào slot bất cứ lúc nào mà không mất thêm phí." onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" onClick={submit} loading={busy} disabled={maint || cost > user.balance} title={maint ? MAINT_HINT : undefined}>Mua {qty} slot · {money(cost)}</Button></>}>
      <div className="stack">
        {maint && <Alert kind="warn">{MAINT_HINT}</Alert>}
        <div className="field">
          <span className="label">Số lượng</span>
          <div className="stepper">
            <Button icon={Minus} aria-label="Giảm" onClick={() => setQty(Math.max(1, qty - 1))} disabled={qty <= 1} />
            <output aria-live="polite">{qty}</output>
            <Button icon={Plus} aria-label="Tăng" onClick={() => setQty(Math.min(20, qty + 1))} disabled={qty >= 20} />
          </div>
          {status && !status.accepting && <small className="hint danger">Hệ thống đang tạm hết chỗ, có thể chưa mua được.</small>}
        </div>
        <div className="field"><span className="label">Gói</span><PlanPicker value={plan} onChange={setPlan} /></div>
        <CouponField context="rent" amount={full} value={coupon} onChange={setCoupon} />
        <CostRow cost={cost} balance={user.balance} original={full} />
      </div>
    </Modal>
  );
}

function RenewDialog({ tab, slot }) {
  const { config, user, act, close } = useApp();
  const [plan, setPlan] = useState('month');
  const [busy, setBusy] = useState(false);
  const [coupon, setCoupon] = useState(null);
  const p = config.plans.find(x => x.id === plan);
  const item = tab || slot;
  const cost = coupon ? coupon.final : p.price;
  const submit = async () => {
    setBusy(true);
    const path = tab ? `/tabs/${tab.id}/renew` : `/slots/${slot.id}/renew`;
    const ok = await act(() => api(path, 'POST', { plan, coupon: tab && coupon ? coupon.code : undefined }), `Đã gia hạn thêm ${p.days} ngày.`);
    setBusy(false);
    if (ok) close();
  };
  return (
    <Modal title={tab ? `Gia hạn "${tab.name}"` : 'Gia hạn slot trống'} desc={`Hạn hiện tại: ${dateTime(item.expires)} (${remaining(item.expires).toLowerCase()}).`} onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" onClick={submit} loading={busy} disabled={cost > user.balance}>Gia hạn · {money(cost)}</Button></>}>
      <div className="stack">
        <PlanPicker value={plan} onChange={setPlan} />
        {tab && <small className="muted">Gia hạn sẽ tự bật lại tab nếu tab đang dừng.</small>}
        {tab && <CouponField context="rent" amount={p.price} value={coupon} onChange={setCoupon} />}
        <CostRow cost={cost} balance={user.balance} original={p.price} />
      </div>
    </Modal>
  );
}

function RenameDialog({ tab }) {
  const { act, close } = useApp();
  const [name, setName] = useState(tab.name);
  const [busy, setBusy] = useState(false);
  const submit = async e => {
    e.preventDefault();
    setBusy(true);
    const ok = await act(() => api('/tabs/' + tab.id, 'PATCH', { name: name.trim() }), 'Đã đổi tên tab.');
    setBusy(false);
    if (ok) close();
  };
  return (
    <Modal title="Đổi tên tab" onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button><Button variant="primary" type="submit" form="rename" loading={busy} disabled={!name.trim()}>Lưu</Button></>}>
      <form id="rename" onSubmit={submit}><Field label="Tên mới"><input value={name} maxLength={60} onChange={e => setName(e.target.value)} data-autofocus /></Field></form>
    </Modal>
  );
}

function ReleaseDialog({ tab }) {
  const { act, close } = useApp();
  const expired = tab.expires <= serverNow();
  return (
    <Confirm title={`Giải phóng "${tab.name}"?`} danger confirmLabel="Giải phóng tab" cancelLabel="Giữ lại" onClose={close}
      onConfirm={() => act(() => api('/tabs/' + tab.id, 'DELETE'), 'Đã giải phóng tab.')}>
      Tab và dữ liệu game đang chạy trong tab sẽ bị xóa.{' '}
      {expired ? 'Tab đã hết hạn nên không còn slot đi kèm.' : 'Slot còn hạn sẽ trở thành slot trống để bạn gắn tab khác — không hoàn tiền.'}
    </Confirm>
  );
}

export function LogsDialog({ tab }) {
  const { close } = useApp();
  const [logs, setLogs] = useState(null);
  const [updated, setUpdated] = useState(0);
  const [err, setErr] = useState('');
  const load = () => api(`/tabs/${tab.id}/logs`).then(d => { setLogs(d.logs); setUpdated(d.updated || 0); setErr(''); }).catch(e => setErr(e.message));
  useEffect(() => {
    load();
    // Logs are uploaded only while someone polls them: every 5 s while this dialog is open.
    const id = setInterval(() => !document.hidden && load(), 5000);
    return () => clearInterval(id);
  }, [tab.id]);
  return (
    <Modal wide title={`Nhật ký: ${tab.name}`} desc={`Nhật ký game${updated ? ` · cập nhật ${dateTime(updated)}` : ''} · tự làm mới mỗi 5 giây`} onClose={close}
      footer={<Button icon={RefreshCw} onClick={load}>Làm mới</Button>}>
      {err && <Alert kind="danger">{err}</Alert>}
      {logs === null ? <Spinner /> : logs ? <pre className="terminal">{logs}</pre> : <Empty title="Chưa có nhật ký" />}
    </Modal>
  );
}

const REGISTRY = { rent: RentDialog, game: ChangeGameDialog, screen: ScreenDialog, schedule: ScheduleDialog, share: ShareDialog, group: GroupDialog, slots: BuySlotsDialog, renew: RenewDialog, rename: RenameDialog, release: ReleaseDialog, logs: LogsDialog, viewer: Viewer };

export function Dialogs({ dialog }) {
  const { tabs } = useApp();
  if (!dialog) return null;
  const C = REGISTRY[dialog.type];
  // Keep tab-bound dialogs fed with the latest polled copy of the tab.
  const tab = dialog.tab && (tabs?.find(t => t.id === dialog.tab.id) || dialog.tab);
  return <C {...dialog} tab={tab} />;
}
