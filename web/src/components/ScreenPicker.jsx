import React, { useState } from 'react';
import { RectangleVertical, RectangleHorizontal, RotateCw } from 'lucide-react';
import { api } from '../api.js';
import { useApp } from '../store.js';
import { Modal, Button } from './ui.jsx';

// "240x320" → [240, 320]
export const screenDims = id => (id || '240x320').split('x').map(Number);
export const orientationOf = id => { const [w, h] = screenDims(id); return w > h ? 'landscape' : 'portrait'; };

// Equivalent size in the other orientation (240x320 ↔ 320x240 …), else the first size of that orientation.
export function rotatedScreen(screens, id, target) {
  const [w, h] = screenDims(id);
  const swap = `${h}x${w}`;
  if (screens.some(s => s.id === swap) && orientationOf(swap) === target) return swap;
  return screens.find(s => s.orientation === target)?.id || id;
}

// Visual orientation toggle + size chips. Used in settings, rent dialog, tab menu and the viewer.
export function ScreenPicker({ screens, value, onChange, compact }) {
  const orient = orientationOf(value);
  const sizes = screens.filter(s => s.orientation === orient);
  return (
    <div className={'screen-picker' + (compact ? ' compact' : '')}>
      <div className="orient" role="radiogroup" aria-label="Hướng màn hình">
        {[['portrait', 'Dọc', RectangleVertical], ['landscape', 'Ngang', RectangleHorizontal]].map(([o, label, I]) => (
          <button key={o} type="button" role="radio" aria-checked={orient === o} className={'orient-btn' + (orient === o ? ' on' : '')}
            onClick={() => orient !== o && onChange(rotatedScreen(screens, value, o))}>
            <I size={22} aria-hidden /><span>{label}</span>
          </button>
        ))}
      </div>
      <div className="chips wrap" role="radiogroup" aria-label="Kích thước màn hình">
        {sizes.map(s => (
          <button key={s.id} type="button" role="radio" aria-checked={value === s.id} className={'chip' + (value === s.id ? ' on' : '')} onClick={() => onChange(s.id)} title={s.label}>
            {(l => l.charAt(0).toUpperCase() + l.slice(1))(s.label.replace(/^(Dọc|Ngang)\s*/, ''))}
          </button>
        ))}
      </div>
    </div>
  );
}

// PATCH {screen}: the game restarts with the new size.
export async function changeScreen(act, tab, screen) {
  return act(() => api('/tabs/' + tab.id, 'PATCH', { screen }), `Đang xoay màn hình "${tab.name}" sang ${screen.replace('x', '×')}…`);
}

export function ScreenDialog({ tab }) {
  const { config, act, close } = useApp();
  const [value, setValue] = useState(tab.screen || '240x320');
  const [busy, setBusy] = useState(false);
  return (
    <Modal title={`Màn hình · ${tab.name}`} desc="Đổi hướng hoặc kích thước màn hình game. Game sẽ khởi động lại, thời hạn giữ nguyên." onClose={close}
      footer={<><Button variant="ghost" onClick={close}>Hủy</Button>
        <Button variant="primary" icon={RotateCw} loading={busy} disabled={value === tab.screen}
          onClick={async () => { setBusy(true); const ok = await changeScreen(act, tab, value); setBusy(false); if (ok) close(); }}>Áp dụng</Button></>}>
      <ScreenPicker screens={config.screens} value={value} onChange={setValue} />
    </Modal>
  );
}
