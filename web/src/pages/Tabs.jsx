import React, { useRef, useState } from 'react';
import { Plus, Layers, Repeat, RotateCw, FolderClock, FolderOpen, Share2, CheckSquare, X, Play, Pause, RotateCcw, Pencil, CalendarPlus, Terminal, Trash2, Search, LayoutGrid, List, Power, PowerOff, Wallet, Clock, Gamepad2, MonitorOff, RefreshCw } from 'lucide-react';
import { api, money, remaining, serverNow, dateTime } from '../api.js';
import { tabState, stateMeta, canRelease, navLabel, tabKind, POLL } from '../tokens.js';
import { useApp } from '../store.js';
import { useMedia, useOnScreen } from '../hooks.js';
import { slotLabel } from '../components/Dialogs.jsx';
import { groupsOf } from '../components/TabTools.jsx';
import { Pager } from '../components/DataTable.jsx';
import { useTabFrame } from '../components/frameSource.js';
import { Button, Menu, StateBadge, Empty, Skeleton, PageHead, Stat, Segmented, Card, useToast, KindBadge, Alert, Badge, MAINT_HINT } from '../components/ui.jsx';

const FILTERS = ['all', 'running', 'idle', 'stopped', 'expired', 'error'];
const sleep = ms => new Promise(r => setTimeout(r, ms));

// What the tab currently runs: the user's JAR filename, or the catalog game name.
export const gameLabel = (t, jars, games) =>
  !t.game ? 'Chưa chọn game' : (t.custom_jar_id && jars.find(j => j.id === t.custom_jar_id)?.filename) || games[t.game]?.name || t.game;
// expiry_alert_hours preference (0 = never warn).
let alertHours = 24;
const soonExpiring = (t, state) => alertHours > 0 && state !== 'expired' && t.expires - serverNow() < alertHours * 3600;

function useTabActions() {
  const { act, open, refresh } = useApp();
  const toast = useToast();
  const setDesired = (t, desired, msg) => act(() => api('/tabs/' + t.id, 'PATCH', { desired }), msg ?? (desired === 'running' ? `Đang khởi động "${t.name}"…` : `Đang dừng "${t.name}"…`));
  const restart = t => act(() => api(`/tabs/${t.id}/restart`, 'POST'), `Đang khởi động lại "${t.name}"…`);
  const setAutoRenew = (t, on) => act(() => api('/tabs/' + t.id, 'PATCH', { auto_renew: on }), on ? `Đã bật tự động gia hạn cho "${t.name}".` : `Đã tắt tự động gia hạn cho "${t.name}".`);
  // "Chơi": open the viewer, starting the tab first when it is paused.
  const play = async (t, state) => {
    if (state === 'stopped' || state === 'error') { if (!(await setDesired(t, 'running', null))) return; }
    open('viewer', { tab: t });
  };
  return { setDesired, restart, open, setAutoRenew, play };
}

function PrimaryAction({ t, state }) {
  const { play, open } = useTabActions();
  if (state === 'idle') return <Button variant="primary" icon={Gamepad2} onClick={() => open('game', { tab: t })}>Chọn game</Button>;
  if (state === 'expired') return <Button variant="primary" icon={CalendarPlus} onClick={() => open('renew', { tab: t })}>Gia hạn</Button>;
  if (state === 'stopping') return <Button disabled loading>Đang dừng</Button>;
  return <Button variant="primary" icon={Play} onClick={() => play(t, state)}>Chơi</Button>;
}

function TabMenu({ t, state }) {
  const { setDesired, restart, open, setAutoRenew } = useTabActions();
  const releasable = canRelease(t);
  const canStop = t.desired === 'running' && state !== 'expired' && state !== 'idle';
  return (
    <Menu label={`Thao tác khác cho ${t.name}`} items={[
      canStop && { label: 'Dừng', icon: Pause, onClick: () => setDesired(t, 'stopped') },
      ['running', 'queued', 'error'].includes(state) && t.game && { label: 'Khởi động lại', icon: RotateCcw, onClick: () => restart(t) },
      state !== 'idle' && { label: 'Đổi game', icon: Repeat, onClick: () => open('game', { tab: t }) },
      { label: `Màn hình · ${(t.screen || '240x320').replace('x', '×')}`, icon: RotateCw, onClick: () => open('screen', { tab: t }) },
      { label: t.restart_at ? `Nhóm & hẹn giờ · ${t.restart_at}` : 'Nhóm & hẹn giờ', icon: FolderClock, onClick: () => open('schedule', { tab: t }) },
      state !== 'expired' && { label: 'Chia sẻ', icon: Share2, onClick: () => open('share', { tab: t }) },
      { label: 'Đổi tên', icon: Pencil, onClick: () => open('rename', { tab: t }) },
      state !== 'expired' && { label: 'Gia hạn', icon: CalendarPlus, onClick: () => open('renew', { tab: t }) },
      t.plan !== 'trial' && state !== 'expired' && { label: t.auto_renew ? 'Tắt tự động gia hạn' : 'Bật tự động gia hạn', icon: RefreshCw, onClick: () => setAutoRenew(t, !t.auto_renew) },
      state !== 'idle' && { label: 'Xem nhật ký', icon: Terminal, onClick: () => open('logs', { tab: t }) },
      { label: 'Giải phóng tab', icon: Trash2, danger: true, disabled: !releasable, hint: releasable ? undefined : 'Hãy dừng tab và đợi tab chuyển sang Tạm dừng trước', onClick: () => open('release', { tab: t }) }
    ]} />
  );
}

// Live thumbnail: still frame every poll_seconds.wall, letterboxed over a blurred copy of itself.
function CardMedia({ t, state, index, total }) {
  const { open } = useApp();
  const live = state === 'running' || state === 'queued';
  const box = useRef(null);
  const onScreen = useOnScreen(box);
  // Thumbnails poll /frame only while the card is visible (the server captures only while someone asks).
  const [frame] = useTabFrame(t.id, POLL.wall, Math.round((index / Math.max(1, total)) * POLL.wall * 1000), live && onScreen);
  const showFrame = live && frame.src;
  return (
    <div ref={box} className={'card-media' + (showFrame ? ' has-frame' : '')}>
      {showFrame ? (
        <button type="button" className="card-media-btn" onClick={() => open('viewer', { tab: t })} aria-label={`Mở màn hình ${t.name}`}>
          <img className="backdrop" src={frame.src} alt="" aria-hidden />
          <img className="fg" src={frame.src} alt="" />
          {frame.fresh && <span className="live-tag">LIVE</span>}
        </button>
      ) : (
        <div className="card-media-empty">
          {state === 'idle' ? <Gamepad2 size={28} aria-hidden /> : <MonitorOff size={26} aria-hidden />}
          <span>{state === 'idle' ? 'Chưa chọn game' : state === 'queued' ? 'Đang khởi động…' : stateMeta(state).label}</span>
          {state === 'idle' && <Button size="sm" variant="primary" icon={Gamepad2} onClick={() => open('game', { tab: t })}>Chọn game</Button>}
        </div>
      )}
    </div>
  );
}

function ExpiryChip({ t, state }) {
  if (state === 'expired') return null;
  if (soonExpiring(t, state)) return <Badge color="warn"><Clock size={12} aria-hidden /> {remaining(t.expires)}</Badge>;
  return <span className="dim small" title={dateTime(t.expires)}>{remaining(t.expires)}</span>;
}

function TabCard({ t, state, index, total, selecting, selected, onSelect }) {
  const { config, jars } = useApp();
  const games = Object.fromEntries(config.games.map(g => [g.id, g]));
  const label = gameLabel(t, jars, games);
  return (
    <article className={'tab-card' + (state === 'running' ? ' running' : '') + (selected ? ' selected' : '')}>
      {selecting && (
        <label className="card-check" title="Chọn tab">
          <input type="checkbox" checked={selected} onChange={() => onSelect(t.id)} aria-label={`Chọn ${t.name}`} />
        </label>
      )}
      <CardMedia t={t} state={state} index={index} total={total} />
      <div className="tab-card-body">
        <div className="row gap-sm">
          <h3 className="ellipsis grow" title={t.name}>{t.name}</h3>
          <StateBadge state={state} />
        </div>
        <div className="tab-sub">
          <span className="ellipsis" title={label}>{label}</span>
          {t.game && <KindBadge kind={tabKind(t, jars, config)} />}
        </div>
        <div className="tab-sub">
          <ExpiryChip t={t} state={state} />
          {t.auto_renew ? <Badge color="info"><RefreshCw size={12} aria-hidden /> Tự gia hạn</Badge> : null}
        </div>
        {(t.group || t.restart_at) && (
          <div className="tab-sub">
            {t.group && <Badge color="muted"><FolderOpen size={12} aria-hidden /> <span className="ellipsis" title={t.group}>{t.group}</span></Badge>}
            {t.restart_at && <Badge color="muted" ><Clock size={12} aria-hidden /> Tự khởi động lại {t.restart_at}</Badge>}
          </div>
        )}
        {t.error && state === 'error' && <p className="tab-error" title={t.error}>{t.error}</p>}
      </div>
      <div className="tab-card-foot">
        <PrimaryAction t={t} state={state} />
        <TabMenu t={t} state={state} />
      </div>
    </article>
  );
}

function TabTable({ rows }) {
  const { config, jars } = useApp();
  const games = Object.fromEntries(config.games.map(g => [g.id, g]));
  return (
    <Card pad={false}>
      <div className="table-wrap">
        <table className="table">
          <thead><tr><th>Tab</th><th>Trạng thái</th><th>Hạn dùng</th><th className="right">Thao tác</th></tr></thead>
          <tbody>
            {rows.map(({ t, state }) => (
              <tr key={t.id}>
                <td><strong className="ellipsis">{t.name}</strong><small className="muted ellipsis">{gameLabel(t, jars, games)}</small></td>
                <td><StateBadge state={state} /></td>
                <td><ExpiryChip t={t} state={state} /></td>
                <td className="right"><div className="row gap-xs end"><PrimaryAction t={t} state={state} /><TabMenu t={t} state={state} /></div></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

const NO_GROUP = '\u0000none';

const PER_PAGE = 24;

export default function Tabs() {
  const { tabs, slots, user, config, open, act, go, prefs, maint } = useApp();
  alertHours = prefs.expiry_alert_hours ?? 24;
  const mobile = useMedia('(max-width: 760px)');
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState('all');
  const [group, setGroup] = useState('all');
  const [view, setView] = useState('grid');
  const [selecting, setSelecting] = useState(false);
  const [sel, setSel] = useState([]);
  const [page, setPage] = useState(0);
  const now = serverNow();

  const head = (actions) => (
    <PageHead title={navLabel('tabs')} desc="Các máy treo bạn đang thuê. Bấm Chơi để xem và điều khiển game.">{actions}</PageHead>
  );
  if (!tabs) return <>{head()}<Skeleton variant="cards" /></>;

  const rows = tabs.map(t => ({ t, state: tabState(t, now) }));
  const groups = groupsOf(tabs);
  const matches = (state, f) => f === 'all' || state === f || (f === 'stopped' && state === 'stopping') || (f === 'running' && state === 'queued');
  const inGroup = t => group === 'all' || (group === NO_GROUP ? !t.group : t.group === group);
  const count = f => rows.filter(r => matches(r.state, f)).length;
  const shown = rows.filter(({ t, state }) => matches(state, filter) && inGroup(t) && t.name.toLowerCase().includes(q.trim().toLowerCase()));
  const freeSlots = slots.filter(s => !s.tab_id && s.expires > now);
  const toStart = rows.filter(r => r.t.desired === 'stopped' && r.t.game && r.state !== 'expired').map(r => r.t);
  const toStop = rows.filter(r => r.t.desired === 'running' && r.state !== 'expired' && r.state !== 'idle').map(r => r.t);
  const runBatch = (ids, action, msg) => act(() => api('/tabs/batch', 'POST', { ids, action }), r => msg(r?.done ?? ids.length));
  const minPrice = Math.min(...config.plans.map(p => p.price));
  const toggle = id => setSel(x => (x.includes(id) ? x.filter(y => y !== id) : [...x, id]));
  const stopSelecting = () => { setSelecting(false); setSel([]); };
  // Group headers only when several groups exist and no single group is filtered. Many tabs are split into pages
  // (PER_PAGE cards, groups kept in order) so the page never builds hundreds of cards and live previews at once.
  const grouped = group === 'all' && groups.length > 0;
  const ordered = grouped ? [...groups.flatMap(g => shown.filter(r => r.t.group === g)), ...shown.filter(r => !r.t.group)] : shown;
  const inSection = g => shown.filter(r => (r.t.group || '') === g);  // whole group, not just this page
  const pages = Math.max(1, Math.ceil(ordered.length / PER_PAGE));
  const pg = Math.min(page, pages - 1);
  const pageRows = ordered.slice(pg * PER_PAGE, (pg + 1) * PER_PAGE);
  const sections = grouped
    ? [...groups.map(g => [g, pageRows.filter(r => r.t.group === g)]), ['', pageRows.filter(r => !r.t.group)]].filter(([, list]) => list.length)
    : [[null, pageRows]];
  const card = ({ t, state }, i) => <TabCard key={t.id} t={t} state={state} index={i} total={shown.length} selecting={selecting} selected={sel.includes(t.id)} onSelect={toggle} />;

  return (
    <>
      {head(<>
        <Button variant="primary" icon={Plus} onClick={() => open('rent')} disabled={maint} title={maint ? MAINT_HINT : undefined}>Thuê tab</Button>
        <Menu label="Thao tác khác" items={[
          { label: 'Mua slot trống', icon: Layers, onClick: () => open('slots'), disabled: maint, hint: maint ? MAINT_HINT : undefined },
          tabs.length > 0 && { label: 'Chọn nhiều tab', icon: CheckSquare, onClick: () => setSelecting(true) },
          { label: `Bật tất cả (${toStart.length})`, icon: Power, disabled: !toStart.length, onClick: () => runBatch(toStart.map(t => t.id), 'start', n => `Đang bật ${n} tab…`) },
          { label: `Dừng tất cả (${toStop.length})`, icon: PowerOff, disabled: !toStop.length, onClick: () => runBatch(toStop.map(t => t.id), 'stop', n => `Đang dừng ${n} tab…`) }
        ]} />
      </>)}

      {tabs.length > 0 && (
        <div className="stats stats-3">
          <Stat label="Đang chạy" value={`${count('running')}/${tabs.length}`} />
          <Stat label="Slot trống" value={freeSlots.length} />
          <Stat label="Số dư" value={money(user.balance)} />
        </div>
      )}

      {user.balance < minPrice && (
        <Alert kind="info" icon={Wallet}>
          Số dư chưa đủ cho gói rẻ nhất ({money(minPrice)}). <button type="button" className="link" onClick={() => go('wallet')}>Nạp tiền</button>
        </Alert>
      )}

      {freeSlots.length > 0 && (
        <Card title={`Slot trống · ${freeSlots.length}`} pad={false}>
          <ul className="slot-list">
            {freeSlots.map(s => (
              <li key={s.id}>
                <strong>{slotLabel(slots, s)}</strong>
                <span className="muted grow" title={dateTime(s.expires)}>{remaining(s.expires)}</span>
                <Button size="sm" variant="ghost" onClick={() => open('renew', { slot: s })}>Gia hạn</Button>
                <Button size="sm" onClick={() => open('rent', { slotId: s.id })} disabled={maint}>Tạo tab</Button>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {tabs.length === 0 ? (
        <Empty image="/art/game-landscape.png" title="Bạn chưa có tab nào"
          action={<Button variant="primary" icon={Plus} onClick={() => open('rent')} disabled={maint} title={maint ? MAINT_HINT : undefined}>Thuê tab đầu tiên</Button>}>
          Thuê một tab để treo game J2ME hoặc Java PC 24/24 và điều khiển từ mọi thiết bị.
        </Empty>
      ) : (
        <>
          <div className="toolbar">
            <label className="search">
              <Search size={16} aria-hidden />
              <input type="search" placeholder="Tìm tab…" value={q} onChange={e => setQ(e.target.value)} aria-label="Tìm tab" />
            </label>
            <div className="chips" role="radiogroup" aria-label="Lọc theo trạng thái">
              {FILTERS.map(id => {
                const n = id === 'all' ? tabs.length : count(id);
                if (id !== 'all' && !n) return null;
                return (
                  <button key={id} type="button" role="radio" aria-checked={filter === id} className={'chip' + (filter === id ? ' on' : '')} onClick={() => setFilter(id)}>
                    {id === 'all' ? 'Tất cả' : stateMeta(id).label} <span>{n}</span>
                  </button>
                );
              })}
            </div>
            <div className="toolbar-end">
              <Button variant={selecting ? 'secondary' : 'ghost'} icon={selecting ? X : CheckSquare} onClick={() => (selecting ? stopSelecting() : setSelecting(true))}>{selecting ? 'Xong' : 'Chọn'}</Button>
              {!mobile && <Segmented label="Kiểu hiển thị" value={view} onChange={setView} options={[['grid', 'Dạng lưới', LayoutGrid], ['list', 'Dạng danh sách', List]]} />}
            </div>
          </div>
          {groups.length > 0 && (
            <div className="chips group-chips" role="radiogroup" aria-label="Lọc theo nhóm">
              <FolderOpen size={16} className="dim" aria-hidden />
              {[['all', 'Mọi nhóm'], ...groups.map(g => [g, g]), [NO_GROUP, 'Chưa có nhóm']].map(([id, label]) => (
                <button key={id} type="button" role="radio" aria-checked={group === id} className={'chip' + (group === id ? ' on' : '')} onClick={() => setGroup(id)} title={label}>
                  <span className="chip-label">{label}</span>
                  <span>{id === 'all' ? tabs.length : tabs.filter(t => (id === NO_GROUP ? !t.group : t.group === id)).length}</span>
                </button>
              ))}
            </div>
          )}

          {shown.length === 0 ? (
            <Empty icon={Search} title="Không có tab phù hợp" action={<Button onClick={() => { setQ(''); setFilter('all'); setGroup('all'); }}>Xóa bộ lọc</Button>} />
          ) : view === 'list' && !mobile ? (
            <><TabTable rows={pageRows} /><Pager page={pg} pages={pages} total={ordered.length} onChange={setPage} unit="tab" /></>
          ) : (
            sections.map(([g, list]) => (
              <section key={g ?? 'all'} className="tab-section">
                {g !== null && (
                  <div className="group-head">
                    <h2 className="ellipsis" title={g || 'Chưa có nhóm'}>{g || 'Chưa có nhóm'}</h2><span className="dim small num">{inSection(g).length} tab</span>
                    {selecting && <button type="button" className="link small" onClick={() => setSel(x => [...new Set([...x, ...inSection(g).map(r => r.t.id)])])}>Chọn cả nhóm</button>}
                  </div>
                )}
                <div className="tab-grid">{list.map(card)}</div>
              </section>
            )).concat(<Pager key="pager" page={pg} pages={pages} total={ordered.length} onChange={setPage} unit="tab" />)
          )}
        </>
      )}

      {selecting && (
        <div className="batch-bar" role="toolbar" aria-label="Thao tác hàng loạt">
          <span className="num"><b>{sel.length}</b> đã chọn</span>
          <button type="button" className="link small" onClick={() => setSel(sel.length === shown.length ? [] : shown.map(r => r.t.id))}>{sel.length === shown.length ? 'Bỏ chọn' : 'Chọn tất cả'}</button>
          <span className="grow" />
          <Button size="sm" icon={Play} disabled={!sel.length} onClick={() => runBatch(sel, 'start', n => `Đang chạy ${n} tab…`)}>Chạy</Button>
          <Button size="sm" icon={Pause} disabled={!sel.length} onClick={() => runBatch(sel, 'stop', n => `Đang dừng ${n} tab…`)}>Dừng</Button>
          <Button size="sm" icon={RotateCcw} disabled={!sel.length} onClick={() => runBatch(sel, 'restart', n => `Đang khởi động lại ${n} tab…`)}><span className="hide-xs">Khởi động lại</span></Button>
          <Button size="sm" icon={FolderOpen} disabled={!sel.length} onClick={() => open('group', { ids: sel })}>Gán nhóm</Button>
          <Button size="sm" variant="ghost" icon={X} aria-label="Thoát chế độ chọn" onClick={stopSelecting} />
        </div>
      )}
    </>
  );
}
