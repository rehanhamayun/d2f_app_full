import { useEffect, useRef, useState } from 'react';
import { X, ChevronLeft, ChevronRight, RefreshCw, PackageOpen } from 'lucide-react';
import { request } from './api.js';
export const human = v => (v || '').toLowerCase().replaceAll('_', ' ').replace(/^./, c => c.toUpperCase());
export const place = l => [l?.city || l?.name, l?.country].filter(Boolean).join(', ');
export const dateTime = v => new Date(v).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
export function Pill({ status }) { return <span className={`ops-pill ops-${status?.toLowerCase()}`}>{human(status)}</span>; }
export function Heading({ label, title, text, children }) { return <div className="page-heading"><div><span className="eyebrow">{label}</span><h1>{title}</h1><p>{text}</p></div><div className="heading-actions">{children}</div></div>; }
export function Empty({ title, text }) { return <div className="ops-empty"><PackageOpen size={30} /><h3>{title}</h3><p>{text}</p></div>; }
export function Pagination({ offset, total, size = 50, onPage }) { return <div className="table-foot table-pagination"><span>{total ? `${offset + 1}–${Math.min(offset + size, total)} of ${total}` : '0 records'}</span><div><button className="button secondary" aria-label="Previous page" disabled={!offset} onClick={() => onPage(Math.max(0, offset - size))}><ChevronLeft size={14} /> Previous</button><button className="button secondary" aria-label="Next page" disabled={offset + size >= total} onClick={() => onPage(offset + size)}>Next <ChevronRight size={14} /></button></div></div>; }
export function Modal({ title, label, children, onClose, busy = false, wide = false }) {
  const ref = useRef(null);
  useEffect(() => {
    const previous = document.activeElement, overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    ref.current?.focus();
    const key = e => {
      if (e.key === 'Escape' && !busy) onClose();
      if (e.key !== 'Tab') return;
      const elements = [...ref.current.querySelectorAll('button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href], [tabindex="0"]')];
      const first = elements[0], last = elements.at(-1);
      if (!first) { e.preventDefault(); return; }
      if (e.shiftKey && (document.activeElement === first || document.activeElement === ref.current)) { e.preventDefault(); last.focus(); }
      if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', key);
    return () => { document.removeEventListener('keydown', key); document.body.style.overflow = overflow; previous?.focus(); };
  }, [busy, onClose]);
  return <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget && !busy) onClose(); }}><section className={`modal ops-modal ${wide ? 'ops-modal-wide' : ''}`} role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} ref={ref}><div className="modal-header"><div><span className="eyebrow">{label}</span><h2>{title}</h2></div><button className="icon-button" disabled={busy} onClick={onClose} aria-label="Close dialog"><X size={20} /></button></div>{children}</section></div>;
}
export function useRemote(path, token, refresh = 0) {
  const [state, setState] = useState({ data: null, loading: true, error: '' });
  const [version, setVersion] = useState(0);
  useEffect(() => {
    let active = true;
    setState(s => ({ ...s, loading: true, error: '' }));
    request(path, { token }).then(data => { if (active) setState({ data, loading: false, error: '' }); }).catch(e => { if (active) setState({ data: null, loading: false, error: e.message }); });
    return () => { active = false; };
  }, [path, token, refresh, version]);
  return { ...state, reload: () => setVersion(v => v + 1) };
}
export function LoadState({ remote, children }) {
  if (remote.loading) return <div className="loading-panel"><span className="spinner dark-spinner" /> Loading records…</div>;
  if (remote.error) return <div className="ops-error" role="alert"><p>{remote.error}</p><button className="button secondary" onClick={remote.reload}><RefreshCw size={15} /> Retry</button></div>;
  return children;
}
export function CustomerPicker({ token, value, onChange }) {
  const [query, setQuery] = useState('');
  const remote = useRemote(`/admin/customers?limit=50&q=${encodeURIComponent(query)}`, token);
  return <div className="ops-customer-picker"><label>Find customer<input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search by name, email or phone" /></label><label>Customer profile<select required value={value} onChange={e => onChange(e.target.value)}><option value="">Choose a customer</option>{remote.data?.customers?.map(c => <option key={c.id} value={c.id}>{c.displayName}{c.email ? ` · ${c.email}` : ''}</option>)}</select></label>{remote.error && <small role="alert">{remote.error}</small>}{remote.data?.total > 50 && <small>Search to narrow {remote.data.total} customer profiles.</small>}</div>;
}
