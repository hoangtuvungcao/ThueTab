import React, { useLayoutEffect, useRef, useState } from 'react';

// Lightweight inline-SVG charts (no chart library). Width follows the container; hover/touch shows a tooltip.
function useWidth() {
  const ref = useRef(null);
  const [w, setW] = useState(600);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setW(Math.max(260, el.clientWidth)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, w];
}
const niceMax = v => {
  if (v <= 0) return 1;
  const p = 10 ** Math.floor(Math.log10(v));
  return Math.ceil(v / p / (v / p > 5 ? 2 : 1)) * p * (v / p > 5 ? 2 : 1);
};
const short = v => (v >= 1e6 ? (v / 1e6).toFixed(v >= 1e7 ? 0 : 1) + 'tr' : v >= 1e3 ? Math.round(v / 1e3) + 'k' : String(v));
const dayLabel = d => d.slice(8, 10) + '/' + d.slice(5, 7);

/**
 * series: [{key, label, color, type: 'bar'|'line', format}]; data: [{date, ...values}]
 */
export function Chart({ data, series, height = 220, title }) {
  const [ref, width] = useWidth();
  const [hover, setHover] = useState(null);
  const pad = { l: 40, r: 12, t: 12, b: 26 };
  const iw = width - pad.l - pad.r, ih = height - pad.t - pad.b;
  const max = niceMax(Math.max(0, ...data.flatMap(d => series.map(s => d[s.key] || 0))));
  const n = data.length || 1;
  const step = iw / n;
  const bars = series.filter(s => s.type !== 'line');
  const bw = Math.max(2, Math.min(18, (step * 0.7) / Math.max(1, bars.length)));
  const y = v => pad.t + ih - (v / max) * ih;
  const x = i => pad.l + step * i + step / 2;
  const every = Math.ceil(n / Math.max(2, Math.floor(iw / 56)));
  const pick = e => {
    const r = e.currentTarget.getBoundingClientRect();
    const px = (e.clientX ?? e.touches?.[0]?.clientX) - r.left;
    const i = Math.floor((px - pad.l) / step);
    setHover(i >= 0 && i < n ? i : null);
  };
  const h = hover != null ? data[hover] : null;
  return (
    <figure className="chart" ref={ref}>
      {title && <figcaption>{title}</figcaption>}
      <div className="chart-legend">{series.map(s => <span key={s.key}><i style={{ background: s.color }} />{s.label}</span>)}</div>
      <div className="chart-box">
        <svg width={width} height={height} role="img" aria-label={title} onMouseMove={pick} onMouseLeave={() => setHover(null)} onTouchStart={pick} onTouchMove={pick}>
          {[0, 0.5, 1].map(f => (
            <g key={f}>
              <line x1={pad.l} x2={width - pad.r} y1={y(max * f)} y2={y(max * f)} className="chart-grid" />
              <text x={pad.l - 6} y={y(max * f) + 4} textAnchor="end" className="chart-axis">{short(max * f)}</text>
            </g>
          ))}
          {data.map((d, i) => (i % every === 0 ? <text key={d.date} x={x(i)} y={height - 8} textAnchor="middle" className="chart-axis">{dayLabel(d.date)}</text> : null))}
          {hover != null && <rect x={pad.l + step * hover} y={pad.t} width={step} height={ih} className="chart-hover" />}
          {bars.map((s, si) => data.map((d, i) => {
            const v = d[s.key] || 0;
            return <rect key={s.key + i} x={x(i) - (bars.length * bw) / 2 + si * bw} y={y(v)} width={bw - 1} height={Math.max(0, pad.t + ih - y(v))} rx="2" fill={s.color} />;
          }))}
          {series.filter(s => s.type === 'line').map(s => (
            <g key={s.key}>
              <polyline fill="none" stroke={s.color} strokeWidth="2" strokeLinejoin="round" points={data.map((d, i) => `${x(i)},${y(d[s.key] || 0)}`).join(' ')} />
              {data.map((d, i) => <circle key={i} cx={x(i)} cy={y(d[s.key] || 0)} r={hover === i ? 4 : n > 40 ? 0 : 2.5} fill={s.color} />)}
            </g>
          ))}
        </svg>
        {h && (
          <div className="chart-tip" style={{ left: Math.min(width - 150, Math.max(0, x(hover) - 70)) }}>
            <strong>{dayLabel(h.date)}/{h.date.slice(0, 4)}</strong>
            {series.map(s => <span key={s.key}><i style={{ background: s.color }} />{s.label}: <b className="num">{s.format ? s.format(h[s.key] || 0) : h[s.key] || 0}</b></span>)}
          </div>
        )}
      </div>
    </figure>
  );
}
