import React, { useEffect, useState } from 'react';
import { Plus, Trash2, ArrowUp, ArrowDown, Save, Check, X, AlertTriangle, Megaphone } from 'lucide-react';
import { api, money } from '../api.js';
import { useApp } from '../store.js';
import { Button, Card, Skeleton, ErrorBox, Segmented, useToast } from '../components/ui.jsx';
import { PlanCards } from './Plans.jsx';

// Same limits as the API models (SiteContent, Support, PlanItem, topup presets).
const L = { announcement: 300, hero_title: 120, hero_subtitle: 400, cta: 40, footer: 200, title: 80, text: 300, q: 200, a: 1000 };
const LISTS = { features: { max: 8, keys: ['title', 'text'], label: 'Tính năng' }, steps: { max: 6, keys: ['title', 'text'], label: 'Các bước' }, faq: { max: 20, keys: ['q', 'a'], label: 'Hỏi đáp' } };
const FIELD_LABEL = { title: 'Tiêu đề', text: 'Mô tả', q: 'Câu hỏi', a: 'Trả lời' };
const SUPPORT = [['hotline', 'Hotline', 30, '0900 000 000'], ['zalo', 'Zalo', 120, 'Số điện thoại hoặc link'], ['telegram', 'Telegram', 120, '@tenkenh hoặc link'], ['facebook', 'Facebook', 200, 'Link trang'], ['email', 'Email', 120, 'hotro@…']];

function validateSite(s) {
  const e = {};
  for (const k of ['hero_title', 'hero_subtitle', 'cta']) if (!s[k]?.trim()) e[k] = 'Không được để trống.';
  for (const k of ['announcement', 'hero_title', 'hero_subtitle', 'cta', 'footer']) if ((s[k] || '').length > L[k]) e[k] = `Tối đa ${L[k]} ký tự.`;
  for (const [list, cfg] of Object.entries(LISTS)) {
    if ((s[list] || []).length > cfg.max) e[list] = `Tối đa ${cfg.max} mục.`;
    (s[list] || []).forEach((it, i) => cfg.keys.forEach(k => {
      if (!it[k]?.trim()) e[`${list}.${i}.${k}`] = 'Không được để trống.';
      else if (it[k].length > L[k]) e[`${list}.${i}.${k}`] = `Tối đa ${L[k]} ký tự.`;
    }));
  }
  return e;
}
function validatePlans(plans) {
  const e = {};
  const ids = plans.map(p => p.id);
  plans.forEach((p, i) => {
    if (!/^[a-z0-9_-]{2,20}$/.test(p.id)) e[`${i}.id`] = '2–20 ký tự a-z, 0-9, _ hoặc -.';
    else if (ids.indexOf(p.id) !== i) e[`${i}.id`] = 'Mã bị trùng.';
    if (!p.name.trim() || p.name.length > 40) e[`${i}.name`] = '1–40 ký tự.';
    if (!Number.isInteger(p.days) || p.days < 1 || p.days > 365) e[`${i}.days`] = '1–365 ngày.';
    if (!Number.isInteger(p.price) || p.price < 0 || p.price > 10000000) e[`${i}.price`] = '0–10.000.000đ.';
    if ((p.badge || '').length > 24) e[`${i}.badge`] = 'Tối đa 24 ký tự.';
  });
  if (!plans.length) e.all = 'Cần ít nhất một gói.';
  else if (!plans.some(p => p.active)) e.all = 'Cần ít nhất một gói đang bán.';
  return e;
}
function validateSupport(s) {
  const e = {};
  for (const [k, , max] of SUPPORT) if ((s[k] || '').length > max) e[k] = `Tối đa ${max} ký tự.`;
  return e;
}
function validateTopup(v) {
  if (!v.length || v.length > 8) return { all: 'Cần 1–8 mức nạp.' };
  if (v.some(x => x < 10000 || x > 5000000)) return { all: 'Mỗi mức từ 10.000đ đến 5.000.000đ.' };
  return {};
}

// Text input/textarea with label, character counter and inline error.
function TextField({ label, value, onChange, max, error, area, placeholder, rows = 3 }) {
  const n = (value || '').length;
  const Tag = area ? 'textarea' : 'input';
  return (
    <div className="field">
      <div className="field-top"><label>{label}</label>{max && <small className={n > max ? 'danger num' : 'dim num'}>{n}/{max}</small>}</div>
      <Tag value={value || ''} placeholder={placeholder} rows={area ? rows : undefined} aria-invalid={error ? true : undefined}
        aria-label={label} onChange={e => onChange(e.target.value)} />
      {error && <small className="danger">{error}</small>}
    </div>
  );
}

// Add / remove / reorder editor for {title,text} or {q,a} items.
function ListEditor({ name, items, onChange, errors }) {
  const cfg = LISTS[name];
  const set = (i, k, v) => onChange(items.map((it, j) => (j === i ? { ...it, [k]: v } : it)));
  const move = (i, d) => { const a = [...items]; [a[i], a[i + d]] = [a[i + d], a[i]]; onChange(a); };
  return (
    <div className="list-editor">
      <div className="field-top"><strong>{cfg.label}</strong><small className="dim num">{items.length}/{cfg.max}</small></div>
      {items.map((it, i) => (
        <div key={i} className="list-item">
          <span className="list-n num">{i + 1}</span>
          <div className="list-fields">
            {cfg.keys.map((k, ki) => (
              <TextField key={k} label={FIELD_LABEL[k]} value={it[k]} max={L[k]} area={ki === 1} rows={2}
                error={errors[`${name}.${i}.${k}`]} onChange={v => set(i, k, v)} />
            ))}
          </div>
          <div className="list-actions">
            <Button size="sm" variant="ghost" icon={ArrowUp} aria-label={`Đưa mục ${i + 1} lên`} disabled={i === 0} onClick={() => move(i, -1)} />
            <Button size="sm" variant="ghost" icon={ArrowDown} aria-label={`Đưa mục ${i + 1} xuống`} disabled={i === items.length - 1} onClick={() => move(i, 1)} />
            <Button size="sm" variant="ghost" icon={Trash2} aria-label={`Xoá mục ${i + 1}`} onClick={() => onChange(items.filter((_, j) => j !== i))} />
          </div>
        </div>
      ))}
      {errors[name] && <small className="danger">{errors[name]}</small>}
      <Button size="sm" icon={Plus} disabled={items.length >= cfg.max} onClick={() => onChange([...items, Object.fromEntries(cfg.keys.map(k => [k, '']))])}>Thêm mục</Button>
    </div>
  );
}

function SaveBar({ state, dirty, invalid, onSave, onReset }) {
  const label = state === 'saving' ? 'Đang lưu…' : invalid ? 'Có lỗi cần sửa' : dirty ? 'Chưa lưu thay đổi' : state === 'saved' ? 'Đã lưu' : 'Không có thay đổi';
  const Icon = invalid ? AlertTriangle : dirty ? null : state === 'saved' ? Check : null;
  return (
    <div className={'save-bar' + (dirty ? ' dirty' : '')}>
      <span className={'save-state' + (invalid ? ' danger' : !dirty && state === 'saved' ? ' ok' : '')} role="status">{Icon && <Icon size={16} aria-hidden />} {label}</span>
      <div className="row gap-sm">
        {dirty && <Button variant="ghost" onClick={onReset}>Hoàn tác</Button>}
        <Button variant="primary" icon={Save} loading={state === 'saving'} disabled={!dirty || invalid} onClick={onSave}>Lưu</Button>
      </div>
    </div>
  );
}

// Draft/save state for one settings key.
function useDraft(key, initial, validate) {
  const { reloadConfig } = useApp();
  const toast = useToast();
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(initial);
  const [state, setState] = useState('idle');
  const errors = validate(draft);
  const dirty = JSON.stringify(draft) !== JSON.stringify(saved);
  const save = async () => {
    setState('saving');
    try {
      const value = await api(`/admin/settings/${key}`, 'PUT', draft);
      setSaved(value);
      setDraft(value);
      setState('saved');
      reloadConfig();
      toast('Đã lưu. Thay đổi có hiệu lực ngay trên web và ứng dụng.', 'success');
    } catch (e) { setState('idle'); toast(e.message, 'error'); }
  };
  return { draft, setDraft, errors, dirty, invalid: Object.keys(errors).length > 0, state, save, reset: () => setDraft(saved) };
}

function SiteEditor({ initial }) {
  const d = useDraft('site', initial, validateSite);
  const s = d.draft;
  const set = (k, v) => d.setDraft({ ...s, [k]: v });
  return (
    <div className="editor-grid">
      <Card title="Nội dung trang chủ">
        <TextField label="Thông báo đầu trang (để trống để ẩn)" value={s.announcement} max={L.announcement} error={d.errors.announcement} onChange={v => set('announcement', v)} />
        <TextField label="Tiêu đề lớn" value={s.hero_title} max={L.hero_title} error={d.errors.hero_title} onChange={v => set('hero_title', v)} />
        <TextField label="Mô tả" area value={s.hero_subtitle} max={L.hero_subtitle} error={d.errors.hero_subtitle} onChange={v => set('hero_subtitle', v)} />
        <TextField label="Nút kêu gọi" value={s.cta} max={L.cta} error={d.errors.cta} onChange={v => set('cta', v)} />
        {Object.keys(LISTS).map(k => <ListEditor key={k} name={k} items={s[k] || []} errors={d.errors} onChange={v => set(k, v)} />)}
        <TextField label="Chân trang" value={s.footer} max={L.footer} error={d.errors.footer} onChange={v => set('footer', v)} />
        <SaveBar {...d} onSave={d.save} onReset={d.reset} />
      </Card>
      <div className="preview-col">
        <small className="muted">Xem trước</small>
        <div className="preview">
          {s.announcement && <div className="announce static"><Megaphone size={16} aria-hidden /><span>{s.announcement}</span></div>}
          <div className="preview-hero">
            <h1>{s.hero_title || 'Tiêu đề'}</h1>
            <p className="muted">{s.hero_subtitle}</p>
            <span className="btn btn-primary">{s.cta || 'Nút'}</span>
          </div>
          {(s.features || []).length > 0 && <div className="preview-pillars">{s.features.map((f, i) => <div key={i}><strong>{f.title}</strong><small className="muted">{f.text}</small></div>)}</div>}
        </div>
      </div>
    </div>
  );
}

function SupportEditor({ initial }) {
  const d = useDraft('support', initial, validateSupport);
  return (
    <Card title="Liên hệ hỗ trợ" className="narrow-card">
      <p className="muted small">Ô nào để trống sẽ được ẩn trên trang chủ, trang Hướng dẫn và ứng dụng.</p>
      {SUPPORT.map(([k, label, max, ph]) => (
        <TextField key={k} label={label} value={d.draft[k]} max={max} placeholder={ph} error={d.errors[k]} onChange={v => d.setDraft({ ...d.draft, [k]: v })} />
      ))}
      <SaveBar {...d} onSave={d.save} onReset={d.reset} />
    </Card>
  );
}

function PlansEditor({ initial }) {
  const d = useDraft('plans', initial.map(p => ({ badge: '', active: true, ...p })), validatePlans);
  const plans = d.draft;
  const set = (i, k, v) => d.setDraft(plans.map((p, j) => (j === i ? { ...p, [k]: v } : p)));
  const move = (i, dir) => { const a = [...plans]; [a[i], a[i + dir]] = [a[i + dir], a[i]]; d.setDraft(a); };
  const num = v => (v === '' ? NaN : Number(v));
  return (
    <>
      <Card title="Bảng giá" pad={false}>
        <div className="table-wrap">
          <table className="table plan-table">
            <thead><tr><th>Mã</th><th>Tên gói</th><th>Số ngày</th><th>Giá (đ)</th><th>Nhãn</th><th>Đang bán</th><th /></tr></thead>
            <tbody>
              {plans.map((p, i) => (
                <tr key={i}>
                  {[['id', 'text', 110], ['name', 'text', 180], ['days', 'number', 80], ['price', 'number', 120], ['badge', 'text', 130]].map(([k, type, w]) => (
                    <td key={k} style={{ minWidth: w }}>
                      <input type={type} inputMode={type === 'number' ? 'numeric' : undefined} value={Number.isNaN(p[k]) ? '' : p[k]} aria-label={`${k} gói ${i + 1}`}
                        aria-invalid={d.errors[`${i}.${k}`] ? true : undefined} title={d.errors[`${i}.${k}`]}
                        onChange={e => set(i, k, type === 'number' ? num(e.target.value) : e.target.value)} />
                      {d.errors[`${i}.${k}`] && <small className="danger">{d.errors[`${i}.${k}`]}</small>}
                    </td>
                  ))}
                  <td><input type="checkbox" checked={p.active} aria-label={`Gói ${i + 1} đang bán`} onChange={e => set(i, 'active', e.target.checked)} /></td>
                  <td><div className="row gap-xs end">
                    <Button size="sm" variant="ghost" icon={ArrowUp} aria-label="Lên" disabled={i === 0} onClick={() => move(i, -1)} />
                    <Button size="sm" variant="ghost" icon={ArrowDown} aria-label="Xuống" disabled={i === plans.length - 1} onClick={() => move(i, 1)} />
                    <Button size="sm" variant="ghost" icon={Trash2} aria-label="Xoá gói" onClick={() => d.setDraft(plans.filter((_, j) => j !== i))} />
                  </div></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="card-pad">
          {d.errors.all && <small className="danger">{d.errors.all}</small>}
          <div><Button size="sm" icon={Plus} onClick={() => d.setDraft([...plans, { id: 'goi-' + (plans.length + 1), name: 'Gói mới', days: 30, price: 10000, badge: '', active: true }])}>Thêm gói</Button></div>
          <SaveBar {...d} onSave={d.save} onReset={d.reset} />
        </div>
      </Card>
      <small className="muted">Xem trước bảng giá</small>
      <PlanCards plans={plans.filter(p => p.active && !Number.isNaN(p.price) && p.days > 0)} onPick={() => {}} />
    </>
  );
}

function TopupEditor({ initial }) {
  const d = useDraft('topup_presets', initial, validateTopup);
  const [add, setAdd] = useState('');
  const v = parseInt(add, 10);
  const addOk = Number.isInteger(v) && v >= 10000 && v <= 5000000 && !d.draft.includes(v);
  return (
    <Card title="Mức nạp nhanh" className="narrow-card">
      <p className="muted small">Các mức tiền gợi ý trên trang Ví (1–8 mức, 10.000đ–5.000.000đ).</p>
      <div className="chips wrap">
        {d.draft.map(x => (
          <span key={x} className="chip on num">{money(x)}
            <button type="button" className="chip-x" aria-label={`Bỏ ${money(x)}`} onClick={() => d.setDraft(d.draft.filter(y => y !== x))}><X size={14} /></button>
          </span>
        ))}
      </div>
      <div className="row gap-sm">
        <input inputMode="numeric" placeholder="Ví dụ 300000" value={add} aria-label="Mức nạp mới" onChange={e => setAdd(e.target.value.replace(/\D/g, ''))}
          onKeyDown={e => { if (e.key === 'Enter' && addOk) { d.setDraft([...d.draft, v].sort((a, b) => a - b)); setAdd(''); } }} />
        <Button icon={Plus} disabled={!addOk || d.draft.length >= 8} onClick={() => { d.setDraft([...d.draft, v].sort((a, b) => a - b)); setAdd(''); }}>Thêm</Button>
      </div>
      {d.errors.all && <small className="danger">{d.errors.all}</small>}
      <SaveBar {...d} onSave={d.save} onReset={d.reset} />
    </Card>
  );
}

export default function AdminContent() {
  const [data, setData] = useState(null);
  const [err, setErr] = useState('');
  const [tab, setTab] = useState('site');
  const load = () => api('/admin/settings').then(setData).catch(e => setErr(e.message));
  useEffect(() => { load(); }, []);
  if (err) return <ErrorBox onRetry={() => { setErr(''); load(); }}>{err}</ErrorBox>;
  if (!data) return <Skeleton variant="rows" count={4} />;
  return (
    <div className="stack">
      <Segmented label="Mục nội dung" value={tab} onChange={setTab} options={[['site', 'Trang chủ'], ['support', 'Liên hệ'], ['plans', 'Bảng giá'], ['topup', 'Mức nạp']]} />
      {tab === 'site' && <SiteEditor initial={data.site} />}
      {tab === 'support' && <SupportEditor initial={data.support} />}
      {tab === 'plans' && <PlansEditor initial={data.plans} />}
      {tab === 'topup' && <TopupEditor initial={data.topup_presets} />}
    </div>
  );
}
