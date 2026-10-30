import React, { useEffect, useRef, useState } from 'react';
import { ChevronUp, ChevronDown, ChevronLeft, ChevronRight, Delete } from 'lucide-react';

// Physical keyboard → key names accepted by POST /tabs/{id}/input and /tabs/input
const KEYMAP = {
  ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', Enter: 'Return', Escape: 'Escape',
  ' ': 'space', Backspace: 'BackSpace', F1: 'F1', F2: 'F2', '*': 'asterisk', '#': 'numbersign'
};
export const keyFromEvent = e => KEYMAP[e.key] || (/^[0-9]$/.test(e.key) ? e.key : null);

const DIGITS = [['1', ''], ['2', 'abc'], ['3', 'def'], ['4', 'ghi'], ['5', 'jkl'], ['6', 'mno'], ['7', 'pqrs'], ['8', 'tuv'], ['9', 'wxyz']];

// Keys the game sees held down (pressed while the finger/key stays down, repeating), not single taps.
export const HOLD_KEYS = new Set(['Up', 'Down', 'Left', 'Right', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);
const HOLD_REFRESH = 400; // ms: "still held" to the server, which lets go by itself if this stops

// Sends keys typed on the physical keyboard while `active`, ignoring form fields. With `hold` (live socket),
// arrows and digits are held for as long as the key is down, like on a phone.
export function useKeyboard(send, active = true, hold = null) {
  useEffect(() => {
    if (!active) return;
    const held = new Map(); // key -> refresh timer
    const release = key => { clearInterval(held.get(key)); held.delete(key); hold?.(key, false); };
    const onKey = e => {
      const t = e.target;
      if (e.ctrlKey || e.metaKey || e.altKey || /INPUT|TEXTAREA|SELECT/.test(t.tagName)) return;
      if (t.tagName === 'BUTTON' && (e.key === 'Enter' || e.key === ' ')) return; // the focused button handles it
      const key = keyFromEvent(e);
      if (!key) return;
      e.preventDefault();
      if (e.repeat || held.has(key)) return;
      if (hold && HOLD_KEYS.has(key) && hold(key, true)) held.set(key, setInterval(() => hold(key, true), HOLD_REFRESH));
      else send(key);
    };
    const onUp = e => { const key = keyFromEvent(e); if (key && held.has(key)) release(key); };
    const releaseAll = () => [...held.keys()].forEach(release);
    window.addEventListener('keydown', onKey);
    window.addEventListener('keyup', onUp);
    window.addEventListener('blur', releaseAll);
    return () => { window.removeEventListener('keydown', onKey); window.removeEventListener('keyup', onUp); window.removeEventListener('blur', releaseAll); releaseAll(); };
  }, [send, active, hold]);
}

// One key with an immediate local "pressed" flash (no waiting for the server). Fires on touch-down, not on
// release (a click only comes when the finger lifts, which felt like lag on phones); held, it repeats like a
// phone keypad so a direction can be held. Keyboard activation (Enter/Space on a focused key) still clicks.
// Only directions and digits repeat: a held OK / soft key / Esc would click through menus.
const REPEAT_AFTER = 350, REPEAT_EVERY = 110, NO_REPEAT = new Set(['Return', 'F1', 'F2', 'Escape', 'BackSpace']);
export function Key({ k, children, label, className = '', base = 'key', onKey, onHold, disabled, repeat = !NO_REPEAT.has(k) }) {
  const [down, setDown] = useState(false);
  const timer = useRef(0);
  const holding = useRef(false);
  const stop = () => {
    clearTimeout(timer.current); clearInterval(timer.current); timer.current = 0; setDown(false);
    if (holding.current) { holding.current = false; onHold?.(k, false); }
  };
  useEffect(() => stop, []);
  const fire = () => onKey(k);
  return (
    <button type="button" className={`${base} ${className}${down ? ' pressed' : ''}`} aria-label={label} title={label} disabled={disabled}
      onPointerDown={e => {
        if (e.button !== 0 || disabled) return;
        e.preventDefault(); // no focus/selection, no delayed click
        e.currentTarget.setPointerCapture?.(e.pointerId);
        setDown(true);
        // Live socket: the game gets the key held down until the finger lifts (moves continuously).
        if (onHold && HOLD_KEYS.has(k) && onHold(k, true)) {
          holding.current = true;
          timer.current = setInterval(() => onHold(k, true), HOLD_REFRESH);
          return;
        }
        fire();
        if (repeat) {
          const again = () => { fire(); timer.current = setTimeout(again, REPEAT_EVERY); };
          timer.current = setTimeout(again, REPEAT_AFTER);
        }
      }}
      onPointerUp={stop} onPointerCancel={stop} onLostPointerCapture={stop}
      onContextMenu={e => e.preventDefault()}
      onClick={e => { if (e.detail === 0) { fire(); setDown(true); setTimeout(() => setDown(false), 160); } }}>{children}</button>
  );
}

// D-pad with OK, plus clear (BackSpace) and Esc; optional soft keys in the top corners.
export function DPad({ onKey, onHold, disabled, soft = false, className = '' }) {
  const p = { onKey, onHold, disabled };
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
export function NumPad({ onKey, onHold, disabled, className = '' }) {
  const p = { onKey, onHold, disabled };
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
