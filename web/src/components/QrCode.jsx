import React, { useEffect, useState } from 'react';
import { Download, Smartphone } from 'lucide-react';
import { Button, Spinner } from './ui.jsx';

// QR code for a URL. The encoder (qrcode-generator, MIT) is loaded on demand so it stays out of the main bundle.
// Rendered as an SVG: dark modules on white with a 4-module quiet zone, readable in both themes.
const QUIET = 4;

export default function QrCode({ value, size = 160, name = 'thuetab-qr', hint = true }) {
  const [svg, setSvg] = useState(null);
  const [err, setErr] = useState('');
  useEffect(() => {
    let alive = true;
    setSvg(null);
    import('qrcode-generator').then(({ default: qrcode }) => {
      const qr = qrcode(0, 'M'); // auto version, ~15% error correction
      qr.addData(value);
      qr.make();
      const n = qr.getModuleCount();
      const total = n + QUIET * 2;
      let d = '';
      for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (qr.isDark(r, c)) d += `M${c + QUIET},${r + QUIET}h1v1h-1z`;
      if (alive) setSvg({ total, d });
    }).catch(() => alive && setErr('Không tạo được mã QR.'));
    return () => { alive = false; };
  }, [value]);

  // PNG download: draw the SVG onto a canvas at 8 px per module.
  const download = () => {
    const scale = 8, px = svg.total * scale;
    const src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(markup(svg));
    const img = new Image();
    img.onload = () => {
      const c = document.createElement('canvas');
      c.width = c.height = px;
      const g = c.getContext('2d');
      g.imageSmoothingEnabled = false;
      g.drawImage(img, 0, 0, px, px);
      const a = document.createElement('a');
      a.href = c.toDataURL('image/png');
      a.download = name + '.png';
      a.click();
    };
    img.src = src;
  };

  if (err) return <p className="muted small">{err}</p>;
  return (
    <div className="qr-box">
      <div className="qr-frame" style={{ width: size, height: size }}>
        {svg ? (
          <svg viewBox={`0 0 ${svg.total} ${svg.total}`} width={size} height={size} role="img" aria-label="Mã QR của link chia sẻ" shapeRendering="crispEdges">
            <rect width={svg.total} height={svg.total} fill="#fff" />
            <path d={svg.d} fill="#000" />
          </svg>
        ) : <Spinner label="" />}
      </div>
      {hint && <p className="qr-hint"><Smartphone aria-hidden /> Mở trên điện thoại: quét mã bằng camera</p>}
      <Button size="sm" icon={Download} disabled={!svg} onClick={download}>Tải ảnh PNG</Button>
    </div>
  );
}

const markup = ({ total, d }) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${total} ${total}" shape-rendering="crispEdges"><rect width="${total}" height="${total}" fill="#fff"/><path d="${d}" fill="#000"/></svg>`;
