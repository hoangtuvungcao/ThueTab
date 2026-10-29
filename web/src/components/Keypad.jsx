import React, { useEffect, useState } from 'react';
import { ChevronUp, ChevronDown, ChevronLeft, ChevronRight, Delete } from 'lucide-react';

// Physical keyboard → key names accepted by POST /tabs/{id}/input and /tabs/input
const KEYMAP = {
  ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', Enter: 'Return', Escape: 'Escape',
  ' ': 'space', Backspace: 'BackSpace', F1: 'F1', F2: 'F2', '*': 'asterisk', '#': 'numbersign'
};
export const keyFromEvent = e => KEYMAP[e.key] || (/^[0-9]$/.test(e.key) ? e.key : null);

const DIGITS = [['1', ''], ['2', 'abc'], ['3', 'def'], ['4', 'ghi'], ['5', 'jkl'], ['6', 'mno'], ['7', 'pqrs'], ['8', 'tuv'], ['9', 'wxyz']];

// Sends keys typed on the physical keyboard while `active`, ignoring form fields.
export function useKeyboard(send, active = true) {
  useEffect(() => {
    if (!active) return;
    const onKey = e => {
      const t = e.target;
      if (e.ctrlKey || e.metaKey || e.altKey || /INPUT|TEXTAREA|SELECT/.test(t.tagName)) return;
      if (t.tagName === 'BUTTON' && (e.key === 'Enter' || e.key === ' ')) return; // the focused button handles it
      const key = keyFromEvent(e);
      if (!key) return;
      e.preventDefault();
      if (!e.repeat) send(key);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [send, active]);
}

// One key with an immediate local "pressed" flash (no waiting for the server).
function Key({ k, children, label, className = '', onKey, disabled }) {
  const [down, setDown] = useState(false);
  return (
    <button type="button" className={`key ${className}${down ? ' pressed' : ''}`} aria-label={label} title={label} disabled={disabled}
      onClick={() => { setDown(true); setTimeout(() => setDown(false), 160); onKey(k); }}>{children}</button>
  );
}

// D-pad with OK, plus clear (BackSpace) and Esc; optional soft keys in the top corners.
export function DPad({ onKey, disabled, soft = false, className = '' }) {
  const p = { onKey, disabled };
  return (
    <div className={'keypad-nav ' + className} role="group" aria-label="Phím điều hướng">
      {soft ? <Key k="F1" className="soft" label="Phím mềm trái (F1)" {...p}>Mềm trái</Key> : <span />}
      <Key k="Up" label="Lên" {...p}><ChevronUp size={18} /></Key>
      {soft ? <Key k="F2" className="soft" label="Phím mềm phải (F2)" {...p}>Mềm phải</Key> : <span />}
      <Key k="Left" label="Trái" {...p}><ChevronLeft size={18} /></Key>
      <Key k="Return" className="ok" label="OK (Enter)" {...p}>OK</Key>
      <Key k="Right" label="Phải" {...p}><ChevronRight size={18} /></Key>
      <Key k="BackSpace" className="soft" label="Xóa (Backspace)" {...p}><Delete size={16} /></Key>
      <Key k="Down" label="Xuống" {...p}><ChevronDown size={18} /></Key>
      <Key k="Escape" className="soft" label="Quay lại (Esc)" {...p}>Esc</Key>
    </div>
  );
}

// 0–9, * and # (Nokia layout).
export function NumPad({ onKey, disabled, className = '' }) {
  const p = { onKey, disabled };
  return (
    <div className={'keypad-num ' + className} role="group" aria-label="Bàn phím số">
      {DIGITS.map(([d, l]) => <Key key={d} k={d} label={`Phím ${d}`} {...p}><b>{d}</b><small>{l}</small></Key>)}
      <Key k="asterisk" label="Phím *" {...p}><b>*</b></Key>
      <Key k="0" label="Phím 0" {...p}><b>0</b><small>␣</small></Key>
      <Key k="numbersign" label="Phím #" {...p}><b>#</b></Key>
    </div>
  );
}

// Full Nokia-style keypad (used by the multi-screen wall).
export default function Keypad({ onKey, disabled, soft = true }) {
  return (
    <div className="keypad" role="group" aria-label="Bàn phím điều khiển">
      <DPad onKey={onKey} disabled={disabled} soft={soft} />
      <NumPad onKey={onKey} disabled={disabled} />
    </div>
  );
}
