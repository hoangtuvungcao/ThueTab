import React, { useEffect, useState } from 'react';
import { Gift, Share2, Users, Coins, UserPlus } from 'lucide-react';
import { api, money, dateTime } from '../api.js';
import { useApp } from '../store.js';
import { Button, Card, Empty, PageHead, Stat, Skeleton, CopyButton, ErrorBox } from '../components/ui.jsx';

export default function Referral() {
  const { config } = useApp();
  const [d, setD] = useState(null);
  const [err, setErr] = useState('');
  const load = () => api('/me/referral').then(setD).catch(e => setErr(e.message));
  useEffect(() => { load(); }, []);
  if (err) return <><PageHead title="Giới thiệu bạn bè" /><ErrorBox onRetry={load}>{err}</ErrorBox></>;
  if (!d) return <><PageHead title="Giới thiệu bạn bè" /><Skeleton variant="rows" count={3} /></>;
  if (!d.enabled || !config.referral?.enabled)
    return <><PageHead title="Giới thiệu bạn bè" /><Empty icon={Gift} title="Chương trình giới thiệu đang tạm dừng">Hãy quay lại sau nhé.</Empty></>;
  const link = location.origin + (d.path.startsWith('/') ? d.path : '/' + d.path);
  const share = () => navigator.share?.({ title: 'ThuêTab', text: 'Treo game Java 24/24 trên đám mây với ThuêTab. Đăng ký qua link của mình nhé:', url: link }).catch(() => {});
  return (
    <>
      <PageHead title="Giới thiệu bạn bè" desc="Mời bạn bè dùng ThuêTab và nhận thưởng vào ví." />
      <Card className="ref-hero">
        <div className="ref-reward">
          <span className="ref-icon"><Gift size={24} aria-hidden /></span>
          <p>Khi bạn bè đăng ký bằng link của bạn và <b>nạp tiền lần đầu</b>, bạn nhận <b className="num">{d.percent}%</b> số tiền họ nạp
            {d.max_bonus ? <> (tối đa <b className="num">{money(d.max_bonus)}</b> mỗi người)</> : null}, cộng thẳng vào ví.</p>
        </div>
        <div className="ref-code">
          <div className="field"><span className="label">Mã giới thiệu</span>
            <div className="code-box"><code className="num">{d.code}</code><CopyButton value={d.code} label="Sao chép mã" /></div></div>
          <div className="field grow min0"><span className="label">Link giới thiệu</span>
            <div className="code-box"><span className="ellipsis mono" title={link}>{link}</span><CopyButton value={link} label="Sao chép link" /></div></div>
        </div>
        {navigator.share && <div><Button variant="primary" icon={Share2} onClick={share}>Chia sẻ link</Button></div>}
      </Card>
      <div className="stats">
        <Stat icon={Users} label="Đã mời" value={d.invited} />
        <Stat icon={Coins} label="Đã nhận thưởng" value={money(d.earned)} />
      </div>
      <Card title={`Bạn bè đã tham gia (${d.friends.length})`} pad={false}>
        {d.friends.length === 0 ? <Empty icon={UserPlus} title="Chưa có ai tham gia">Gửi link cho bạn bè để bắt đầu nhận thưởng.</Empty> : (
          <ul className="drawer-list pad-list">
            {d.friends.map((f, i) => <li key={i}><span className="avatar" aria-hidden>{(f.name || '?')[0].toUpperCase()}</span><strong className="ellipsis grow" title={f.name}>{f.name}</strong><small className="muted num">{dateTime(f.created)}</small></li>)}
          </ul>
        )}
      </Card>
    </>
  );
}
