import { useEffect, useRef, useState } from 'react';

// Runs `fn` every `seconds` while the page is visible, and once again when it becomes visible.
export function usePoll(fn, seconds, enabled = true) {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    if (!enabled) return;
    const tick = () => { if (!document.hidden) ref.current(); };
    const id = setInterval(tick, seconds * 1000);
    document.addEventListener('visibilitychange', tick);
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', tick); };
  }, [seconds, enabled]);
}

export function useMedia(query) {
  const [match, setMatch] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const m = window.matchMedia(query);
    const on = () => setMatch(m.matches);
    m.addEventListener('change', on);
    return () => m.removeEventListener('change', on);
  }, [query]);
  return match;
}

// Hash router: #/tabs, #/wallet … so refresh and the back button keep the current page.
export function useRoute(fallback) {
  const read = () => location.hash.replace(/^#\/?/, '').split('?')[0] || fallback;
  const [route, setRoute] = useState(read);
  useEffect(() => {
    const on = () => setRoute(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return [route, r => { if (location.hash !== '#/' + r) location.hash = '/' + r; else setRoute(r); window.scrollTo(0, 0); }];
}

// Query parameters of the hash route, e.g. #/register?ref=ABC → { ref: 'ABC' }.
export const hashQuery = () => Object.fromEntries(new URLSearchParams(location.hash.split('?')[1] || ''));

// True while the element is on screen (IntersectionObserver), so off-screen thumbnails stop polling.
export function useOnScreen(ref, margin = '200px') {
  const [on, setOn] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el || !('IntersectionObserver' in window)) { setOn(true); return; }
    const io = new IntersectionObserver(([e]) => setOn(e.isIntersecting), { rootMargin: margin });
    io.observe(el);
    return () => io.disconnect();
  }, [ref.current]);
  return on;
}
