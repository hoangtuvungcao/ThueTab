import React, { useEffect, useMemo, useState } from 'react';
import { ArrowUp, ArrowDown, ChevronLeft, ChevronRight } from 'lucide-react';
import { Empty } from './ui.jsx';

/**
 * columns: [{ key, label, render(row), sort(row) → comparable, className, hideMobile }]
 * Sortable headers, optional row selection and row click. On phones each row becomes a card
 * (labels come from data-label), so nothing scrolls sideways. Long lists are split into pages of `pageSize`.
 */
export default function DataTable({ columns, rows, rowKey = r => r.id, onRowClick, selectable, selected = [], onSelect, empty = 'Không có dữ liệu phù hợp', initialSort, pageSize = 20 }) {
  const [sort, setSort] = useState(initialSort || null); // { key, dir: 1 | -1 }
  const [page, setPage] = useState(0);
  const sorted = useMemo(() => {
    if (!sort) return rows;
    const col = columns.find(c => c.key === sort.key);
    if (!col?.sort) return rows;
    return [...rows].sort((a, b) => {
      const x = col.sort(a), y = col.sort(b);
      return (x > y ? 1 : x < y ? -1 : 0) * sort.dir;
    });
  }, [rows, sort, columns]);
  const pages = Math.max(1, Math.ceil(sorted.length / pageSize));
  // A new search/filter or sort shrinks the list: never stay on a page past the end.
  useEffect(() => { if (page > pages - 1) setPage(pages - 1); }, [pages]);
  useEffect(() => { setPage(0); }, [sort]);
  const shown = sorted.slice(page * pageSize, page * pageSize + pageSize);
  const allOn = selectable && rows.length > 0 && rows.every(r => selected.includes(rowKey(r)));
  const toggle = id => onSelect(selected.includes(id) ? selected.filter(x => x !== id) : [...selected, id]);
  const head = c => {
    if (!c.sort) return c.label;
    const on = sort?.key === c.key;
    return (
      <button type="button" className={'th-sort' + (on ? ' on' : '')} onClick={() => setSort(on ? (sort.dir === 1 ? { key: c.key, dir: -1 } : null) : { key: c.key, dir: 1 })}
        aria-label={`Sắp xếp theo ${c.label}`}>
        {c.label}{on && (sort.dir === 1 ? <ArrowUp size={12} aria-hidden /> : <ArrowDown size={12} aria-hidden />)}
      </button>
    );
  };
  if (!rows.length) return <Empty title={empty} />;
  return (
    <div className="table-wrap">
      <table className="table rt">
        <thead>
          <tr>
            {selectable && <th className="th-check"><input type="checkbox" checked={allOn} aria-label="Chọn tất cả" onChange={() => onSelect(allOn ? [] : rows.map(rowKey))} /></th>}
            {columns.map(c => <th key={c.key} className={(c.className || '') + (c.hideMobile ? ' hide-mobile' : '')} aria-sort={sort?.key === c.key ? (sort.dir === 1 ? 'ascending' : 'descending') : undefined}>{head(c)}</th>)}
          </tr>
        </thead>
        <tbody>
          {shown.map(r => {
            const id = rowKey(r);
            return (
              <tr key={id} className={(onRowClick ? 'clickable' : '') + (selected.includes(id) ? ' selected' : '')}
                onClick={onRowClick ? e => { if (!e.target.closest('button,a,input,select,label,.menu')) onRowClick(r); } : undefined}
                onKeyDown={onRowClick ? e => { if (e.key === 'Enter' && e.target === e.currentTarget) onRowClick(r); } : undefined}
                tabIndex={onRowClick ? 0 : undefined}>
                {selectable && <td className="td-check"><input type="checkbox" checked={selected.includes(id)} aria-label="Chọn dòng" onChange={() => toggle(id)} /></td>}
                {columns.map(c => <td key={c.key} data-label={c.label} className={(c.className || '') + (c.hideMobile ? ' hide-mobile' : '')}>{c.render ? c.render(r) : r[c.key]}</td>)}
              </tr>
            );
          })}
        </tbody>
      </table>
      <Pager page={page} pages={pages} total={sorted.length} onChange={setPage} />
    </div>
  );
}

/** "‹ Trước · Trang 2/5 · 87 dòng · Sau ›" — hidden when everything fits on one page. */
export function Pager({ page, pages, total, onChange, unit = 'dòng' }) {
  if (pages <= 1) return null;
  return (
    <nav className="pager" aria-label="Phân trang">
      <button type="button" className="btn btn-sm btn-ghost" disabled={page === 0} onClick={() => onChange(page - 1)}><ChevronLeft size={16} aria-hidden /> Trước</button>
      <span className="muted num">Trang {page + 1}/{pages} · {total} {unit}</span>
      <button type="button" className="btn btn-sm btn-ghost" disabled={page >= pages - 1} onClick={() => onChange(page + 1)}>Sau <ChevronRight size={16} aria-hidden /></button>
    </nav>
  );
}
