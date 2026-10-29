import React from 'react';
import { MessageCircle, Send, Mail, Phone, ThumbsUp } from 'lucide-react';
import { navLabel } from '../tokens.js';
import { useApp } from '../store.js';
import { Card, PageHead, Button } from '../components/ui.jsx';

export function SupportLinks() {
  const { config } = useApp();
  const s = config.support || {};
  const links = [
    s.hotline && { href: `tel:${s.hotline.replace(/[^\d+]/g, '')}`, icon: Phone, label: `Hotline ${s.hotline}` },
    s.zalo && { href: /^https?:/.test(s.zalo) ? s.zalo : `https://zalo.me/${s.zalo.replace(/\D/g, '')}`, icon: MessageCircle, label: 'Zalo' + (/^https?:/.test(s.zalo) ? '' : ` ${s.zalo}`) },
    s.telegram && { href: /^https?:/.test(s.telegram) ? s.telegram : `https://t.me/${s.telegram.replace(/^@/, '')}`, icon: Send, label: 'Telegram' + (/^https?:/.test(s.telegram) ? '' : ` ${s.telegram}`) },
    s.facebook && { href: /^https?:/.test(s.facebook) ? s.facebook : `https://facebook.com/${s.facebook}`, icon: ThumbsUp, label: 'Facebook' },
    s.email && { href: `mailto:${s.email}`, icon: Mail, label: s.email }
  ].filter(Boolean);
  if (!links.length) return null;
  return (
    <ul className="support">
      {links.map(l => <li key={l.href}><a href={l.href} target="_blank" rel="noopener noreferrer"><l.icon size={16} aria-hidden /> {l.label}</a></li>)}
    </ul>
  );
}

export const hasSupport = config => Object.values(config.support || {}).some(Boolean);

const KEYS = [['Mũi tên', 'D-pad Lên/Xuống/Trái/Phải'], ['Enter', 'OK (phím giữa)'], ['F1 / F2', 'Phím mềm trái / phải'], ['Backspace', 'Xóa (C)'], ['Esc', 'Quay lại'], ['0 – 9, *, #', 'Bàn phím số'], ['Space', 'Phím cách']];

export default function Help() {
  const { config, go } = useApp();
  return (
    <>
      <PageHead title={navLabel('help')} desc="Bắt đầu treo game trong vài phút." />
      {config.site?.steps?.length > 0 && <ol className="steps">
        {config.site.steps.map((st, i) => <li key={i}><span className="step-n">{i + 1}</span><div className="min0"><strong>{st.title}</strong><p className="muted">{st.text}</p></div></li>)}
      </ol>}
      <div className="two-col">
        <Card title="Phím điều khiển">
          <dl className="kv">{KEYS.map(([k, v]) => <div key={k}><dt><kbd>{k}</kbd></dt><dd>{v}</dd></div>)}</dl>
          <p className="muted small">Trên màn hình chơi, bạn cũng có thể chạm hoặc vuốt trực tiếp vào hình game.</p>
        </Card>
        <Card title="Câu hỏi thường gặp">
          <div className="faq">{(config.site?.faq || []).map((f, i) => <details key={i}><summary>{f.q}</summary><p className="muted">{f.a}</p></details>)}</div>
        </Card>
      </div>
      <Card title="Cần thêm trợ giúp?">
        <p className="muted">Gửi yêu cầu hỗ trợ và trao đổi trực tiếp với đội ngũ ThuêTab. Bạn sẽ nhận thông báo khi có trả lời.</p>
        <div><Button variant="primary" icon={MessageCircle} onClick={() => go('support')}>Mở trang Hỗ trợ</Button></div>
        {hasSupport(config) && <SupportLinks />}
      </Card>
    </>
  );
}
