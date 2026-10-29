import React, { useEffect, useState } from 'react';
import { Download as DownloadIcon, MonitorSmartphone, Share, PlusSquare, CheckCircle2, Globe, Smartphone, Monitor, Laptop } from 'lucide-react';
import { fileSize, dateTime, apiUrl } from '../api.js';
// Download URLs from /config are API paths (/api/downloads/…): resolve them on the API origin.
const dlUrl = u => (/^https?:/.test(u || '') ? u : apiUrl(u || ''));
import { useApp } from '../store.js';
import { Button, Card, PageHead, Alert } from '../components/ui.jsx';

// Best-effort OS + browser detection (User-Agent Client Hints when available, else the UA string).
export function detectPlatform() {
  const ua = navigator.userAgent || '';
  const hint = navigator.userAgentData?.platform || '';
  const src = hint + ' ' + ua;
  const ios = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  const os = ios ? 'iOS' : /Android/i.test(src) ? 'Android' : /Windows/i.test(src) ? 'Windows' : /Mac/i.test(src) ? 'macOS' : /Linux|CrOS/i.test(src) ? 'Linux' : 'Khác';
  const browser = /SamsungBrowser/i.test(ua) ? 'Samsung Internet' : /coc_coc|CocCoc/i.test(ua) ? 'Cốc Cốc' : /OPR\/|Opera/i.test(ua) ? 'Opera'
    : /Edg(A|iOS)?\//i.test(ua) ? 'Edge' : /Firefox|FxiOS/i.test(ua) ? 'Firefox' : /CriOS|Chrome/i.test(ua) ? 'Chrome' : /Safari/i.test(ua) ? 'Safari' : 'Trình duyệt';
  const chromium = !ios && /Chrome|Chromium|Edg|OPR|SamsungBrowser|coc_coc/i.test(ua);
  return { os, browser, ios, chromium, mobile: ios || os === 'Android' };
}

const OS_ICON = { Windows: Monitor, macOS: Laptop, Linux: Monitor, Android: Smartphone, iOS: Smartphone };
// One-line install steps per platform, shown under each download button.
const HOW = {
  windows: 'Giải nén file .zip, mở thư mục ThueTab rồi chạy ThueTab.exe. Nếu Windows cảnh báo: Thông tin thêm → Vẫn chạy.',
  linux: 'Giải nén (tar xf ThueTab-Linux.tar.gz) rồi chạy ThueTab/ThueTab.x86_64.',
  macos: 'Giải nén, kéo ThuêTab vào Applications. Lần đầu: chuột phải vào ứng dụng → Mở.',
  android: 'Mở file .apk vừa tải, cho phép "Cài ứng dụng không rõ nguồn" nếu được hỏi, rồi chọn Cài đặt.'
};
const howTo = d => HOW[(d.platform || '').toLowerCase()];

const matchOs = (d, os) => (d.platform || d.label || '').toLowerCase().includes(os.toLowerCase().replace('macos', 'mac'));
const installed = () => matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

function useInstallPrompt() {
  const [prompt, setPrompt] = useState(() => window.__installPrompt || null);
  useEffect(() => {
    const on = () => setPrompt(window.__installPrompt || null);
    window.addEventListener('tt-installable', on);
    window.addEventListener('appinstalled', on);
    return () => { window.removeEventListener('tt-installable', on); window.removeEventListener('appinstalled', on); };
  }, []);
  const install = async () => {
    const p = window.__installPrompt;
    if (!p) return;
    p.prompt();
    await p.userChoice.catch(() => null);
    window.__installPrompt = null;
    setPrompt(null);
  };
  return [prompt, install];
}

// Steps for "add to home screen / install" in the current browser.
function PwaSteps({ env, canPrompt, install }) {
  if (installed()) return <p className="row gap-sm success-text"><CheckCircle2 size={18} aria-hidden /> ThuêTab đã được cài trên thiết bị này.</p>;
  if (canPrompt) return <div><Button variant="primary" size="lg" icon={DownloadIcon} onClick={install}>Cài đặt ứng dụng</Button></div>;
  if (env.ios)
    return (
      <ol className="howto">
        {env.browser !== 'Safari' && <li>Mở trang này bằng <b>Safari</b> (iOS chỉ cho cài ứng dụng web từ Safari).</li>}
        <li>Bấm nút <b>Chia sẻ</b> <Share size={14} aria-label="biểu tượng chia sẻ" /> ở thanh dưới.</li>
        <li>Chọn <b>Thêm vào Màn hình chính</b> <PlusSquare size={14} aria-hidden />, rồi bấm <b>Thêm</b>.</li>
      </ol>
    );
  if (env.browser === 'Firefox')
    return env.mobile
      ? <ol className="howto"><li>Mở menu <b>⋮</b> của Firefox.</li><li>Chọn <b>Cài đặt</b> hoặc <b>Thêm vào màn hình chính</b>.</li></ol>
      : <p className="muted">Firefox trên máy tính chưa hỗ trợ cài ứng dụng web. Bạn có thể ghim tab (chuột phải → <b>Ghim thẻ</b>) hoặc mở bằng Chrome/Edge để cài.</p>;
  return (
    <ol className="howto">
      <li>Mở menu trình duyệt <b>{env.mobile ? '⋮' : '⋮ / ⋯'}</b>.</li>
      <li>Chọn <b>{env.mobile ? 'Thêm vào màn hình chính' : 'Cài đặt ThuêTab'}</b> (hoặc <b>Ứng dụng → Cài đặt trang này</b>).</li>
    </ol>
  );
}

export default function Download() {
  const { config } = useApp();
  const env = detectPlatform();
  const [prompt, install] = useInstallPrompt();
  const builds = config.downloads || [];
  const native = builds.find(d => matchOs(d, env.os));
  const Icon = OS_ICON[env.os] || MonitorSmartphone;
  const canPrompt = env.chromium && !!prompt;

  return (
    <>
      <PageHead title="Tải ứng dụng" desc="Chơi ThuêTab như một ứng dụng riêng trên điện thoại và máy tính." />
      <Card className="dl-hero">
        <div className="dl-hero-icon"><Icon size={28} aria-hidden /></div>
        <div className="dl-hero-body">
          <small className="muted">Đề xuất cho {env.os} · {env.browser}</small>
          {native ? (
            <>
              <h2>ThuêTab cho {env.os}</h2>
              <p className="muted">Ứng dụng gốc, mở nhanh và chạy mượt nhất trên máy của bạn.</p>
              <div className="row gap-md wrap">
                <a className="btn btn-primary btn-lg" href={dlUrl(native.url)} download><DownloadIcon size={18} aria-hidden /> Tải {native.label || 'bản cài'}</a>
                <small className="muted num">{native.size ? fileSize(native.size) : ''}{native.updated ? ` · cập nhật ${dateTime(native.updated)}` : ''}</small>
              </div>
              {howTo(native) && <small className="muted dl-how">{howTo(native)}</small>}
            </>
          ) : (
            <>
              <h2>Cài ThuêTab từ trình duyệt</h2>
              <p className="muted">Không cần tải file: ứng dụng web mở toàn màn hình, có biểu tượng riêng và tự cập nhật.</p>
              <PwaSteps env={env} canPrompt={canPrompt} install={install} />
            </>
          )}
        </div>
        <img className="dl-art" src="/art/game-landscape@3x.png" width="960" height="720" alt="" aria-hidden />
      </Card>

      <div className="dl-grid">
        {builds.map(d => {
          const I = OS_ICON[Object.keys(OS_ICON).find(os => matchOs(d, os))] || MonitorSmartphone;
          return (
            <Card key={d.file || d.url} className="dl-card">
              <div className="dl-card-head"><span className="dl-icon"><I size={20} aria-hidden /></span>
                <div className="min0"><strong className="ellipsis" title={d.label}>{d.label || d.platform}</strong>
                  <small className="muted num">{d.size ? fileSize(d.size) : ''}{d.updated ? ` · ${dateTime(d.updated)}` : ''}</small></div></div>
              {howTo(d) && <small className="muted dl-how">{howTo(d)}</small>}
              <a className="btn" href={dlUrl(d.url)} download><DownloadIcon size={16} aria-hidden /> Tải xuống</a>
            </Card>
          );
        })}
        {native && (
          <Card className="dl-card">
            <div className="dl-card-head"><span className="dl-icon"><Globe size={20} aria-hidden /></span>
              <div className="min0"><strong>Cài từ trình duyệt</strong><small className="muted">Mọi thiết bị · không cần tải file</small></div></div>
            <PwaSteps env={env} canPrompt={canPrompt} install={install} />
          </Card>
        )}
      </div>
      {builds.length === 0 && <Alert>Ứng dụng gốc cho Windows, Android và các nền tảng khác sẽ xuất hiện tại đây khi phát hành. Trong lúc chờ, hãy cài ThuêTab từ trình duyệt như hướng dẫn ở trên.</Alert>}
    </>
  );
}
