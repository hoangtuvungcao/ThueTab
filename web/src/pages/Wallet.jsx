import React, { useEffect, useRef, useState } from 'react';
import { Wallet as WalletIcon, QrCode, PauseCircle, Receipt, ArrowDownLeft, ArrowUpRight, Loader2, CheckCircle2, XCircle } from 'lucide-react';
import { api, money, dateTime } from '../api.js';
import { navLabel, ORDER_STATUS } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Card, Empty, PageHead, Alert, Badge, CopyButton, Skeleton, Field, useToast, CouponField } from '../components/ui.jsx';
import { SupportLinks } from './Help.jsx';
import { Pager, usePaged } from '../components/DataTable.jsx';

const OrderBadge = ({ s }) => { const m = ORDER_STATUS[s] || { label: s, color: 'dim' }; return <Badge color={m.color}>{m.label}</Badge>; };

function OrderPanel({ order, onDone }) {
  const { act, config, user, go } = useApp();
  const [busy, setBusy] = useState('');
  if (order.status === 'paid')
    return (
      <div className="order-done" role="status">
        <span className="done-ring"><CheckCircle2 size={36} aria-hidden /></span>
        <strong>Nạp thành công {money(order.amount)}!</strong>
        <p className="muted">Số dư hiện tại: <b className="accent">{money(user.balance)}</b></p>
        <div className="row gap-sm wrap center"><Button variant="primary" onClick={() => go('tabs')}>Về tab của tôi</Button><Button onClick={onDone}>Nạp thêm</Button></div>
      </div>
    );
  if (order.status === 'cancelled')
    return (
      <div className="stack">
        <Alert kind="info">Đơn {order.code} đã được hủy.</Alert>
        <div><Button onClick={onDone}>Tạo đơn mới</Button></div>
      </div>
    );
  const cancel = async () => { setBusy('cancel'); await act(() => api(`/wallet/orders/${order.id}`, 'DELETE'), 'Đã hủy đơn nạp.'); setBusy(''); };
  const rows = [['Ngân hàng', order.bank], ['Số tài khoản', order.account], ['Chủ tài khoản', order.account_name], ['Số tiền', String(order.amount), money(order.amount)], ['Nội dung chuyển khoản', order.code]];
  return (
    <div className="order">
      {order.is_live && (
        <div className="order-live">
          <img className="qr" src={order.qr_url} alt={`Mã QR chuyển khoản ${money(order.amount)}`} width="220" height="220" />
          <dl className="kv">
            {rows.map(([k, v, shown]) => v ? (
              <div key={k}><dt>{k}</dt><dd><span className={k.startsWith('Nội dung') ? 'mono strong' : ''}>{shown || v}</span><CopyButton value={v} label={`Sao chép ${k.toLowerCase()}`} /></dd></div>
            ) : null)}
          </dl>
        </div>
      )}
      {order.is_live && <Alert kind="warn">Ghi đúng nội dung <b className="mono">{order.code}</b> để hệ thống tự cộng tiền.</Alert>}
      <p className="row gap-sm muted"><Loader2 size={16} className="spin" aria-hidden />
        <span>Đang chờ thanh toán đơn <b className="mono">{order.code}</b>… {config.auto_topup ? 'Tiền tự cộng sau 5–30 giây, không cần báo admin.' : 'Trang tự cập nhật khi tiền vào ví.'}</span></p>
      <div className="row gap-sm"><Button variant="danger-ghost" size="sm" icon={XCircle} loading={busy === 'cancel'} onClick={cancel}>Hủy đơn</Button><Button variant="ghost" size="sm" onClick={onDone}>Để sau</Button></div>
    </div>
  );
}

export default function WalletPage() {
  const { wallet, user, config, act } = useApp();
  const toast = useToast();
  const presets = config.topup_presets?.length ? config.topup_presets : [20000, 50000, 100000, 200000, 500000];
  const [amount, setAmount] = useState(presets[1] ?? presets[0]);
  const [orderId, setOrderId] = useState(null);
  const orderPage = usePaged(wallet?.orders || []);
  const ledgerPage = usePaged(wallet?.ledger || []);
  const [coupon, setCoupon] = useState(null);
  const [busy, setBusy] = useState(false);
  const order = wallet?.orders.find(o => o.id === orderId);
  const prevStatus = useRef(null);

  useEffect(() => {
    if (order && prevStatus.current === 'pending' && order.status === 'paid') toast(`Nạp thành công ${money(order.amount)}.`, 'success');
    prevStatus.current = order?.status ?? null;
  }, [order?.status]);

  if (!wallet) return <><PageHead title={navLabel('wallet')} /><Skeleton variant="rows" count={4} /></>;
  const minPrice = Math.min(...config.plans.map(p => p.price));
  const valid = Number.isInteger(amount) && amount >= 10000 && amount <= 5000000;
  const create = async () => {
    setBusy(true);
    const o = await act(() => api('/wallet/orders', 'POST', { amount, coupon: coupon?.code }));
    if (o) setCoupon(null);
    setBusy(false);
    if (o) setOrderId(o.id);
  };

  return (
    <>
      <PageHead title={navLabel('wallet')} desc="Nạp tiền, xem lịch sử giao dịch và đơn nạp." />
      <div className="wallet-grid">
        <Card className="balance-card">
          <div className="stat-label"><WalletIcon size={15} aria-hidden /> Số dư hiện tại</div>
          <div className="balance-value">{money(user.balance)}</div>
          <p className="muted">Tiền trong ví dùng để thuê tab, mua slot và gia hạn.</p>
          {user.balance < minPrice && <Alert kind="warn">Số dư chưa đủ cho gói rẻ nhất ({money(minPrice)}). Hãy nạp thêm để thuê hoặc gia hạn tab.</Alert>}
        </Card>

        <Card title="Nạp tiền">
          {!config.payment_ready ? (
            <div className="paused">
              <span className="paused-icon"><PauseCircle size={22} aria-hidden /></span>
              <div><strong>Nạp tiền đang tạm ngưng</strong>
                <p className="muted">Bạn vẫn dùng được số dư hiện có để thuê và gia hạn tab. Vui lòng quay lại sau.</p>
                <SupportLinks /></div>
            </div>
          ) : order ? (
            <OrderPanel order={order} onDone={() => setOrderId(null)} />
          ) : (
            <div className="stack">
              <div className="choice-grid presets" role="radiogroup" aria-label="Số tiền nạp">
                {presets.map(v => (
                  <button key={v} type="button" role="radio" aria-checked={amount === v} className={'choice' + (amount === v ? ' on' : '')} onClick={() => setAmount(v)}>{money(v)}</button>
                ))}
              </div>
              <Field label="Hoặc nhập số tiền (VNĐ)" hint="Từ 10.000đ đến 5.000.000đ">
                <input type="number" inputMode="numeric" min={10000} max={5000000} step={1000} value={amount || ''} onChange={e => setAmount(parseInt(e.target.value, 10) || 0)} />
              </Field>
              <CouponField context="topup" amount={valid ? amount : 0} value={coupon} onChange={setCoupon} />
              {coupon && valid && <p className="topup-bonus num">Bạn nạp <b>{money(amount)}</b>, nhận <b className="success-text">{money(amount + (coupon.bonus || 0))}</b> vào ví.</p>}
              <Button variant="primary" icon={QrCode} disabled={!valid} loading={busy} onClick={create}>Tạo đơn nạp {valid ? money(amount) : ''}</Button>
              <small className="muted">Chuyển khoản qua VietQR. {config.auto_topup ? 'Tiền tự cộng sau 5–30 giây, không cần báo admin.' : 'Tiền được cộng sau khi giao dịch được xác nhận.'}</small>
            </div>
          )}
        </Card>
      </div>

      <Card title="Đơn nạp gần đây" pad={false}>
        {wallet.orders.length === 0 ? <Empty icon={Receipt} title="Chưa có đơn nạp" /> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Mã đơn</th><th>Số tiền</th><th>Trạng thái</th><th className="hide-mobile">Thời gian</th><th /></tr></thead>
              <tbody>
                {orderPage.rows.map(o => (
                  <tr key={o.id}>
                    <td className="mono">{o.code}</td>
                    <td>{money(o.amount)}</td>
                    <td><OrderBadge s={o.status} /></td>
                    <td className="hide-mobile">{dateTime(o.created)}</td>
                    <td className="right">{o.status === 'pending' && (
                      <div className="row gap-xs end">
                        {config.payment_ready && <Button size="sm" onClick={() => { setOrderId(o.id); window.scrollTo({ top: 0, behavior: 'smooth' }); }}>Tiếp tục</Button>}
                        <Button size="sm" variant="ghost" onClick={() => act(() => api(`/wallet/orders/${o.id}`, 'DELETE'), 'Đã hủy đơn nạp.')}>Hủy</Button>
                      </div>)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <Pager {...orderPage.pager} unit="đơn" />
          </div>
        )}
      </Card>

      <Card title="Lịch sử giao dịch" pad={false}>
        {wallet.ledger.length === 0 ? <Empty icon={Receipt} title="Chưa có giao dịch" /> : (
          <ul className="ledger">
            {ledgerPage.rows.map(l => (
              <li key={l.id}>
                <span className={'ledger-icon ' + (l.amount >= 0 ? 'in' : 'out')} aria-hidden>{l.amount >= 0 ? <ArrowDownLeft size={16} /> : <ArrowUpRight size={16} />}</span>
                <div className="grow min0"><strong className="ellipsis">{l.description}</strong><small className="muted">{dateTime(l.created)}</small></div>
                <span className={'amount ' + (l.amount >= 0 ? 'in' : 'out')}>{l.amount >= 0 ? '+' : '−'}{money(Math.abs(l.amount))}</span>
              </li>
            ))}
          </ul>
        )}
        {wallet.ledger.length > 0 && <Pager {...ledgerPage.pager} unit="giao dịch" />}
      </Card>
    </>
  );
}
