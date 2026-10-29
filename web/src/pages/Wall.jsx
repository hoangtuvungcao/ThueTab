import React, { useCallback, useMemo, useRef, useState } from 'react';
import { ArrowLeft, MonitorOff, Gamepad2, CheckSquare, Square, FolderOpen } from 'lucide-react';
import { api, serverNow } from '../api.js';
import { tabState, tabKind, POLL, navLabel } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Card, Empty, PageHead, Skeleton, StateBadge, KindBadge, useToast } from '../components/ui.jsx';
import Keypad, { useKeyboard } from '../components/Keypad.jsx';
import { Screen } from '../components/Viewer.jsx';
import { groupsOf } from '../components/TabTools.jsx';
import { useTabFrame } from '../components/frameSource.js';
import { useOnScreen } from '../hooks.js';


function Thumb({ t, index, total, kind, selected, onToggle, onOpen }) {
  // Stagger start times so tiles don't all hit the server in the same tick.
  const box = useRef(null);
  const onScreen = useOnScreen(box);
  const [frame, onLoad] = useTabFrame(t.id, POLL.wall, Math.round((index / Math.max(1, total)) * POLL.wall * 1000), onScreen);
  const state = tabState(t, serverNow());
  return (
    <article ref={box} className={'thumb' + (selected ? ' on' : '')}>
      <button type="button" className="thumb-screen" onClick={onOpen} aria-label={`Mở màn hình ${t.name}`}>
        <Screen w={frame.w} h={frame.h} kind={kind} fresh={frame.fresh}
          media={frame.src ? <img src={frame.src} onLoad={onLoad} alt="" className={'screen-media' + (frame.fresh ? '' : ' stale')} draggable={false} /> : null}>
          {!frame.src && <div className="screen-msg"><MonitorOff size={20} aria-hidden /><small>{state === 'queued' ? 'Đang khởi động…' : 'Chờ hình…'}</small></div>}
        </Screen>
      </button>
      <label className="thumb-foot">
        <input type="checkbox" checked={selected} onChange={onToggle} />
        <span className="ellipsis grow">{t.name}</span>
        {frame.fresh ? <span className="live on" title="Đang nhận hình" /> : <StateBadge state={state} />}
      </label>
    </article>
  );
}

export default function Wall() {
  const { tabs, jars, config, open, go, prefs } = useApp();
  const toast = useToast();
  const now = serverNow();
  const [groupF, setGroupF] = useState('all');
  const running = useMemo(() => (tabs || []).filter(t => ['running', 'queued'].includes(tabState(t, now))), [tabs]);
  const groups = groupsOf(running);
  const live = groupF === 'all' ? running : running.filter(t => t.group === groupF);
  const [picked, setPicked] = useState(null); // null = all live tabs selected
  const selected = (picked ?? live.map(t => t.id)).filter(id => live.some(t => t.id === id));
  const lastErr = useRef(0);

  const send = useCallback(key => {
    if (!selected.length) return toast('Chọn ít nhất một tab để điều khiển.', 'error');
    api('/tabs/input', 'POST', { tab_ids: selected.slice(0, 20), key }).catch(e => {
      if (Date.now() - lastErr.current > 3000) { lastErr.current = Date.now(); toast(e.message, 'error'); }
    });
  }, [selected.join()]);
  useKeyboard(send, selected.length > 0);

  if (!tabs) return <><PageHead title={navLabel('wall')} /><Skeleton variant="cards" /></>;
  const toggle = id => setPicked(selected.includes(id) ? selected.filter(x => x !== id) : [...selected, id]);
  const all = selected.length === live.length;

  return (
    <>
      <PageHead title={navLabel('wall')} desc={`Theo dõi mọi tab đang chạy cùng lúc (ảnh làm mới mỗi ${POLL.wall} giây, tối đa một yêu cầu mỗi tab). Bấm vào màn hình để mở xem trực tiếp.`}>
        <Button icon={ArrowLeft} onClick={() => go('tabs')}>Danh sách tab</Button>
      </PageHead>
      {live.length === 0 ? (
        <Empty icon={MonitorOff} title="Không có tab nào đang chạy" action={<Button onClick={() => go('tabs')}>Về danh sách tab</Button>}>
          Bật một tab trong danh sách để xem màn hình tại đây.
        </Empty>
      ) : (
        <>
        {groups.length > 0 && (
          <div className="chips group-chips" role="radiogroup" aria-label="Nhóm">
            <FolderOpen size={16} className="dim" aria-hidden />
            {[['all', 'Mọi nhóm'], ...groups.map(g => [g, g])].map(([id, label]) => (
              <button key={id} type="button" role="radio" aria-checked={groupF === id} className={'chip' + (groupF === id ? ' on' : '')} title={label}
                onClick={() => { setGroupF(id); setPicked(null); }}>
                <span className="chip-label">{label}</span><span className="num">{id === 'all' ? running.length : running.filter(t => t.group === id).length}</span>
              </button>
            ))}
          </div>
        )}
        <div className="wall">
          <div className="wall-grid" style={prefs.wall_columns && prefs.wall_columns !== 'auto' ? { gridTemplateColumns: `repeat(${prefs.wall_columns}, minmax(0, 1fr))` } : undefined}>
            {live.map((t, i) => (
              <Thumb key={t.id} t={t} index={i} total={live.length} kind={tabKind(t, jars, config)}
                selected={selected.includes(t.id)} onToggle={() => toggle(t.id)} onOpen={() => open('viewer', { tab: t })} />
            ))}
          </div>
          <Card className="wall-control" title={<span className="row gap-sm"><Gamepad2 size={16} aria-hidden /> Điều khiển đồng bộ</span>}
            actions={<Button size="sm" variant="ghost" icon={all ? Square : CheckSquare} onClick={() => setPicked(all ? [] : live.map(t => t.id))}>{all ? 'Bỏ chọn' : 'Chọn tất cả'}</Button>}>
            <p className="muted small">Mỗi phím được gửi tới <b>{selected.length}</b>/{live.length} tab đã chọn{live.length > 20 ? ' (tối đa 20)' : ''}. Bàn phím máy tính cũng dùng được.</p>
            <Keypad onKey={send} disabled={!selected.length} />
          </Card>
        </div>
        </>
      )}
    </>
  );
}
