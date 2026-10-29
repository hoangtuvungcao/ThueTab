import React, { useEffect, useState } from 'react';
import { useMedia } from '../hooks.js';
import { ArrowRight, Clock, Gamepad2, LayoutGrid, ChevronUp, ChevronDown, ChevronLeft, ChevronRight, Gauge, RotateCw, ShieldCheck, Smartphone, Zap } from 'lucide-react';
import { money } from '../api.js';
import { BRAND } from '../tokens.js';
import { useApp } from '../store.js';
import { Button } from '../components/ui.jsx';
import { Logo, StatusPill, ThemeToggle } from '../components/Shell.jsx';
import { PlanCards } from './Plans.jsx';
import { SupportLinks, hasSupport } from './Help.jsx';
import Download from './Download.jsx';

// Product mock: original pixel-art scenes in the real viewer frame. Crossfades portrait ↔ landscape every 6 s
// to show screen rotation (static when the user prefers reduced motion).
function ProductMock() {
  const reduce = useMedia('(prefers-reduced-motion: reduce)');
  const [land, setLand] = useState(false);
  useEffect(() => {
    if (reduce) return;
    const t = setInterval(() => setLand(l => !l), 6000);
    return () => clearInterval(t);
  }, [reduce]);
  const K = ({ children, className = '' }) => <span className={'mk ' + className}>{children}</span>;
  return (
    <figure className="mock" aria-label="Màn chơi ThuêTab: xem và điều khiển game từ trình duyệt">
      <div className="mock-bar">
        <span className="mock-dots" aria-hidden><i /><i /><i /></span>
        <span className="mock-title">Tab 1 · Game của bạn</span>
        <span className="mock-chip"><span className="dot" />Đang chạy</span>
      </div>
      <div className="mock-body">
        <div className="mock-device">
          <div className={'mock-screen' + (land ? ' land' : '')}>
            <img className="art art-p" src="/art/game-portrait@3x.png" width="720" height="960" alt="" />
            <img className="art art-l" src="/art/game-landscape@3x.png" width="960" height="720" alt="" />
            <span className="live-tag">LIVE</span>
            <span className="scan" aria-hidden />
          </div>
          <div className="mock-softkeys" aria-hidden><span>◤ Trái</span><small className="num">{land ? 'Ngang 320×240' : 'Dọc 240×320'}</small><span>Phải ◥</span></div>
        </div>
        <div className="mock-pad" aria-hidden>
          <div className="mock-dpad">
            <span /><K><ChevronUp size={16} /></K><span />
            <K><ChevronLeft size={16} /></K><K className="ok">OK</K><K><ChevronRight size={16} /></K>
            <span /><K><ChevronDown size={16} /></K><span />
          </div>
          <div className="mock-keys">{['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'].map(k => <K key={k}><b>{k}</b></K>)}</div>
        </div>
      </div>
      <figcaption className="mock-caption"><RotateCw size={14} aria-hidden /> Dọc ↔ Ngang: đổi hướng màn hình game bất cứ lúc nào</figcaption>
    </figure>
  );
}

// Column count that never leaves a card alone on the last row (4 → 4/2/1, 3 → 3/1, 6 → 3/2, …).
export const colsClass = n => (n % 4 === 0 ? 'cols-4' : n % 3 === 0 ? 'cols-3' : n === 2 ? 'cols-2' : n === 5 ? 'cols-3' : 'cols-auto');

const PILLAR_ICONS = [Clock, Gauge, RotateCw, LayoutGrid, Gamepad2, ShieldCheck, Smartphone, Zap];

// Highlights "24/24" (or the last word) of the admin-editable hero title with the brand gradient.
function HeroTitle({ text }) {
  const m = text.match(/^(.*?)(24\/24)(.*)$/);
  if (m) return <h1>{m[1]}<span className="grad">{m[2]}</span>{m[3]}</h1>;
  return <h1>{text}</h1>;
}

export function LandHeader() {
  const { openAuth } = useApp();
  const go = id => { if (location.hash.startsWith('#/download')) { location.hash = '/'; setTimeout(() => document.getElementById(id)?.scrollIntoView(), 50); } else document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' }); };
  const link = (id, text) => <a href={'#' + id} onClick={e => { e.preventDefault(); go(id); }}>{text}</a>;
  return (
    <header className="land-head">
      <div className="land-wrap row">
        <Logo onClick={e => { e.preventDefault(); location.hash = '/'; window.scrollTo({ top: 0, behavior: 'smooth' }); }} />
        <nav className="land-nav" aria-label="Trang chủ">{link('features', 'Tính năng')}{link('pricing', 'Bảng giá')}{link('faq', 'Hỏi đáp')}<a href="#/download">Tải ứng dụng</a></nav>
        <div className="row gap-sm push">
          <ThemeToggle />
          <Button variant="ghost" onClick={() => openAuth('login')}>Đăng nhập</Button>
          <Button variant="primary" className="hide-xs" onClick={() => openAuth('register')}>Đăng ký</Button>
        </div>
      </div>
    </header>
  );
}

export function LandFooter() {
  const { config } = useApp();
  return (
    <footer className="land-foot">
      <div className="land-wrap foot-grid">
        <div><Logo onClick={e => { e.preventDefault(); location.hash = '/'; window.scrollTo({ top: 0 }); }} />{config.site?.footer && <p className="muted small">{config.site.footer}</p>}</div>
        <div><h3>Sản phẩm</h3><ul className="foot-links"><li><a href="#features">Tính năng</a></li><li><a href="#pricing">Bảng giá</a></li><li><a href="#faq">Hỏi đáp</a></li><li><a href="#/download">Tải ứng dụng</a></li></ul></div>
        {hasSupport(config) && <div><h3>Hỗ trợ</h3><SupportLinks /></div>}
      </div>
      <div className="land-wrap foot-bottom dim small">© {new Date().getFullYear()} ThuêTab</div>
    </footer>
  );
}

export default function Landing({ page = 'home' }) {
  const { config, openAuth } = useApp();
  const site = config.site || {};
  if (page === 'download')
    return <div className="landing"><LandHeader /><main className="land-wrap section"><Download /></main><LandFooter /></div>;
  const minPerDay = Math.min(...config.plans.map(p => Math.round(p.price / p.days)));
  const go = id => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  return (
    <div className="landing">
      <LandHeader />
      <main>
        <div className="hero-grid land-wrap">
          <section className="hero">
            <StatusPill />
            <HeroTitle text={site.hero_title || BRAND.tagline} />
            {site.hero_subtitle && <p className="lead">{site.hero_subtitle}</p>}
            <div className="row gap-sm wrap">
              <Button variant="primary" size="lg" onClick={() => openAuth('register')}>{site.cta || 'Bắt đầu'} <ArrowRight size={16} aria-hidden /></Button>
              <Button size="lg" variant="ghost" onClick={() => go('pricing')}>Xem bảng giá</Button>
            </div>
            {config.plans.length > 0 && <p className="dim small num">Chỉ từ {money(minPerDay)}/ngày</p>}
          </section>
          <ProductMock />
        </div>

        {site.features?.length > 0 && (
          <section id="features" className="land-wrap section">
            <div className={'pillars ' + colsClass(site.features.length)}>
              {site.features.map((f, i) => {
                const I = PILLAR_ICONS[i % PILLAR_ICONS.length];
                return <div key={i} className="pillar"><span className="pillar-icon"><I size={20} aria-hidden /></span><h3>{f.title}</h3><p className="muted">{f.text}</p></div>;
              })}
            </div>
          </section>
        )}

        {site.steps?.length > 0 && (
          <section className="land-wrap section">
            <div className="section-head"><h2>Bắt đầu trong {site.steps.length} bước</h2></div>
            <ol className={'steps ' + colsClass(site.steps.length)}>
              {site.steps.map((st, i) => <li key={i}><span className="step-n">{i + 1}</span><div className="min0"><strong>{st.title}</strong><p className="muted">{st.text}</p></div></li>)}
            </ol>
          </section>
        )}

        <section id="pricing" className="land-wrap section">
          <div className="section-head"><h2>Bảng giá</h2></div>
          <PlanCards onPick={() => openAuth('register')} />
        </section>

        {site.faq?.length > 0 && (
          <section id="faq" className="land-wrap section narrow">
            <div className="section-head"><h2>Câu hỏi thường gặp</h2></div>
            <div className="faq card card-pad">{site.faq.map((f, i) => <details key={i}><summary>{f.q}</summary><p className="muted">{f.a}</p></details>)}</div>
          </section>
        )}

        <section className="land-wrap section">
          <div className="cta-band">
            <div className="min0"><h2>{site.hero_title || BRAND.tagline}</h2></div>
            <Button variant="primary" size="lg" onClick={() => openAuth('register')}>{site.cta || 'Bắt đầu'} <ArrowRight size={16} aria-hidden /></Button>
          </div>
        </section>
      </main>
      <LandFooter />
    </div>
  );
}
