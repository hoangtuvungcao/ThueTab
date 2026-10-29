import React from 'react';
import { Check, Layers, Gift } from 'lucide-react';
import { money } from '../api.js';
import { navLabel } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Card, PageHead } from '../components/ui.jsx';

// Plan cards; `plans` can be passed directly (admin live preview), otherwise config.plans.
export function PlanCards({ onPick, plans: given }) {
  const { config } = useApp();
  const plans = (given || config.plans).filter(p => p.active !== false);
  if (!plans.length) return null;
  const anyBadge = plans.some(p => p.badge);
  const best = plans.reduce((a, p) => (p.price / p.days < a.price / a.days ? p : a), plans[0]);
  const specs = ['Chạy 24/24, kể cả khi tắt máy', 'Điều khiển từ xa: chạm, phím, gõ chữ', 'Xem nhiều màn hình cùng lúc', 'Hỗ trợ J2ME & Java PC'];
  return (
    <div className={'plan-grid ' + (plans.length % 4 === 0 ? 'cols-4' : plans.length % 3 === 0 ? 'cols-3' : plans.length === 2 ? 'cols-2' : 'cols-auto')}>
      {plans.map(p => {
        const tag = anyBadge ? p.badge : p.id === best.id ? 'Tiết kiệm nhất' : '';
        return (
          <article key={p.id} className={'plan' + (tag ? ' best' : '')}>
            {tag && <span className="plan-tag" title={tag}>{tag}</span>}
            <h3 className="ellipsis" title={p.name}>{p.name}</h3>
            <div className="plan-price num">{money(p.price)}<small> / {p.days} ngày</small></div>
            <p className="muted small num">≈ {money(Math.round(p.price / p.days))} mỗi ngày</p>
            <ul className="checks">{specs.map(s => <li key={s}><Check size={16} aria-hidden /><span>{s}</span></li>)}</ul>
            <Button variant={tag ? 'primary' : 'secondary'} onClick={() => onPick(p.id)}>Chọn gói {p.days} ngày</Button>
          </article>
        );
      })}
    </div>
  );
}

export default function Plans() {
  const { open, config, user } = useApp();
  return (
    <>
      <PageHead title={navLabel('plans')} desc="Giá thuê cho mỗi tab. Thanh toán bằng số dư ví, không tự động gia hạn." />
      <PlanCards onPick={plan => open('rent', { plan })} />
      <div className="two-col">
        <Card title="Mua slot trống">
          <p className="muted">Slot là chỗ giữ sẵn với cùng mức giá theo gói. Bạn có thể mua nhiều slot một lần rồi gắn tab vào bất cứ lúc nào, hoặc đổi game mà không mất thêm phí.</p>
          <Button icon={Layers} onClick={() => open('slots')}>Mua slot</Button>
        </Card>
        <Card title="Dùng thử">
          <p className="muted">Tài khoản mới có thể được quản trị viên duyệt dùng thử miễn phí {config.trial_minutes} phút, một lần duy nhất.</p>
          {user?.trial_approved && !user.trial_used
            ? <Button variant="primary" icon={Gift} onClick={() => open('rent')}>Dùng thử {config.trial_minutes} phút</Button>
            : <small className="dim">{user?.trial_used ? 'Bạn đã dùng lượt thử.' : 'Tài khoản của bạn chưa được duyệt dùng thử.'}</small>}
        </Card>
      </div>
    </>
  );
}
