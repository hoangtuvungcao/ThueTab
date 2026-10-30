import React, { useEffect, useState } from 'react';
import { Cpu, MemoryStick, HardDrive, ArrowUp, ArrowDown, Eye, Radio, LayoutGrid, Server } from 'lucide-react';
import { api, fileSize } from '../api.js';
import { Card, Badge, Skeleton, Stat, Empty } from '../components/ui.jsx';
import { Pager } from '../components/DataTable.jsx';

const TABS_PER_PAGE = 10;

const REFRESH_MS = 5000;
const rate = bps => `${fileSize(Math.max(0, bps || 0))}/s`;
// Sizes given in MB: shown as GB from 1 GB up ("15,4 GB" rather than "15784.0 MB").
const mb = v => (v >= 1024 ? `${(v / 1024).toLocaleString('vi-VN', { maximumFractionDigits: 1 })} GB` : `${Math.round(v || 0)} MB`);
const pct = (used, total) => (total ? Math.round((used / total) * 100) : 0);
const uptime = s => {
  if (!s) return '—';
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return d ? `${d} ngày ${h} giờ` : h ? `${h} giờ ${m} phút` : `${m} phút`;
};
// Green under 70 %, amber under 90 %, red above: the same thresholds for CPU, RAM and disk. Green, not the accent:
// with a red/pink accent theme a 4 % bar would look like an alarm.
const tone = p => (p >= 90 ? 'danger' : p >= 70 ? 'warn' : 'success');

function Meter({ icon: Icon, label, value, detail }) {
  const p = Math.min(100, Math.max(0, value));
  return (
    <div className="sys-meter">
      <div className="sys-meter-head"><span><Icon size={15} aria-hidden /> {label}</span><b className="num">{p}%</b></div>
      <div className="meter wide" role="meter" aria-label={label} aria-valuenow={p} aria-valuemin={0} aria-valuemax={100}>
        <span style={{ width: `${p}%`, background: `var(--${tone(p)})` }} />
      </div>
      {detail && <small className="muted num">{detail}</small>}
    </div>
  );
}

function WorkerCard({ w }) {
  const s = w.system || {};
  const [page, setPage] = useState(0);
  const pages = Math.max(1, Math.ceil(w.tabs.length / TABS_PER_PAGE));
  const p = Math.min(page, pages - 1);
  const has = s.cores != null;
  return (
    <Card className="sys-worker"
      title={<span className="row gap-sm"><Server size={16} aria-hidden /> {w.id}</span>}
      actions={<Badge color={w.online ? 'success' : 'danger'} dot>{w.online ? 'Trực tuyến' : 'Mất kết nối'}</Badge>}>
      {!has ? <p className="muted">Chưa có số liệu — máy chủ cần chạy worker bản mới.</p> : (
        <>
          <div className="sys-meters">
            <Meter icon={Cpu} label={`CPU · ${s.cores} nhân`} value={Math.round(s.cpu || 0)} detail={`Tải ${(s.load || []).join(' / ')}`} />
            <Meter icon={MemoryStick} label="RAM" value={pct(s.mem_used_mb, s.mem_total_mb)}
              detail={`${mb(s.mem_used_mb)} / ${mb(s.mem_total_mb)}${s.swap_total_mb ? ` · swap ${mb(s.swap_used_mb)} / ${mb(s.swap_total_mb)}` : ''}`} />
            {s.disk && <Meter icon={HardDrive} label="Ổ đĩa (dữ liệu)" value={pct(s.disk.used_mb, s.disk.total_mb)}
              detail={`${mb(s.disk.used_mb)} / ${mb(s.disk.total_mb)} · còn ${mb(s.disk.total_mb - s.disk.used_mb)}`} />}
            {s.docker_disk && s.docker_disk.total_mb !== s.disk?.total_mb && <Meter icon={HardDrive} label="Ổ đĩa Docker"
              value={pct(s.docker_disk.used_mb, s.docker_disk.total_mb)} detail={`${mb(s.docker_disk.used_mb)} / ${mb(s.docker_disk.total_mb)}`} />}
          </div>
          <div className="sys-facts">
            <span><ArrowUp size={14} aria-hidden /> Tải lên <b className="num">{rate(s.net_tx_bps)}</b></span>
            <span><ArrowDown size={14} aria-hidden /> Tải xuống <b className="num">{rate(s.net_rx_bps)}</b></span>
            <span><LayoutGrid size={14} aria-hidden /> Tab <b className="num">{w.running}/{w.capacity}</b></span>
            <span>Hoạt động <b>{uptime(s.uptime)}</b></span>
          </div>
          {w.tabs.length > 0 && (
            <div className="table-wrap">
              <table className="table sys-tabs">
                <thead><tr><th>Tab</th><th className="right">CPU</th><th className="right">RAM</th></tr></thead>
                <tbody>{w.tabs.slice(p * TABS_PER_PAGE, (p + 1) * TABS_PER_PAGE).map(t => (
                  <tr key={t.tab_id}><td className="ellipsis" title={t.name || t.tab_id}>{t.name || <code>{t.tab_id.slice(0, 8)}</code>}</td>
                    <td className="right num">{t.cpu}%</td><td className="right num">{mb(t.mem_mb)}</td></tr>
                ))}</tbody>
              </table>
              <Pager page={p} pages={pages} total={w.tabs.length} onChange={setPage} unit="tab" />
            </div>
          )}
        </>
      )}
    </Card>
  );
}

/** Live system view for the admin overview: refreshed every 5 s while the page is visible. */
export default function SystemPanel() {
  const [d, setD] = useState(null);
  const [err, setErr] = useState('');
  useEffect(() => {
    let alive = true, timer;
    const load = async () => {
      if (!document.hidden) {
        try { const x = await api('/admin/system'); if (alive) { setD(x); setErr(''); } }
        catch (e) { if (alive) setErr(e.message); }
      }
      if (alive) timer = setTimeout(load, REFRESH_MS);
    };
    load();
    return () => { alive = false; clearTimeout(timer); };
  }, []);
  if (!d) return err ? <Empty icon={Server} title="Không tải được số liệu hệ thống">{err}</Empty> : <Skeleton variant="rows" count={3} />;
  const l = d.live;
  return (
    <section className="sys" aria-label="Hệ thống">
      <div className="stats">
        <Stat icon={LayoutGrid} label="Tab đang chạy" value={`${d.tabs.running}/${d.tabs.total}`} />
        <Stat icon={Eye} label="Đang xem trực tiếp" value={l.viewers} hint={`${l.tabs_watched} tab · ${l.video_viewers} xem bằng video`} />
        <Stat icon={ArrowUp} label="Băng thông luồng hình" value={rate(l.out_bps)} hint="Gửi tới người xem" />
        <Stat icon={Radio} label="Luồng từ máy chủ game" value={l.streams_in} hint={`${rate(l.in_bps)} · ${l.thumbs} ô xem trước`} />
      </div>
      <div className="sys-grid">{d.workers.map(w => <WorkerCard key={w.id} w={w} />)}</div>
    </section>
  );
}
