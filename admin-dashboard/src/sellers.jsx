import { useMemo, useState } from 'react';
import { Check, Store, Plus, ShieldCheck, ShieldOff, RotateCcw, X, ClipboardCheck } from 'lucide-react';
import { request } from './api.js';
import { Empty, Modal, Pill, dateTime, useRemote, LoadState, CustomerPicker } from './operations-ui.jsx';
import { money } from './commerce.jsx';

const FILTERS = ['ALL', 'PENDING', 'APPROVED', 'SUSPENDED', 'REJECTED'];
const pct = bps => `${(bps / 100).toFixed(bps % 100 === 0 ? 0 : 1)}%`;

// Seller applications and admin-registered sellers for the Marketplace tab.
export function SellersPanel({ token, notify, refreshKey }) {
  const [filter, setFilter] = useState('ALL');
  const [review, setReview] = useState(null);
  const [note, setNote] = useState(null); // { seller, action }
  const [register, setRegister] = useState(false);
  const remote = useRemote('/admin/commerce/sellers', token, refreshKey);

  const sellers = remote.data || [];
  const counts = useMemo(() => {
    const map = Object.fromEntries(FILTERS.map(f => [f, 0]));
    for (const seller of sellers) { map.ALL += 1; map[seller.status] = (map[seller.status] || 0) + 1; }
    return map;
  }, [sellers]);
  const shown = filter === 'ALL' ? sellers : sellers.filter(s => s.status === filter);

  async function patch(id, body, message) {
    await request(`/admin/commerce/sellers/${id}`, { token, method: 'PATCH', body: JSON.stringify(body) });
    remote.reload();
    notify(message);
  }

  return <>
    <div className="sellers-toolbar">
      <div className="sellers-filters" role="tablist" aria-label="Seller status filter">
        {FILTERS.map(value => (
          <button
            key={value}
            role="tab"
            aria-selected={filter === value}
            className={`sellers-filter ${filter === value ? 'sellers-filter-active' : ''}`}
            onClick={() => setFilter(value)}
          >
            {value === 'ALL' ? 'All' : value.charAt(0) + value.slice(1).toLowerCase()}
            <span>{counts[value]}</span>
          </button>
        ))}
      </div>
      <button className="button primary" onClick={() => setRegister(true)}><Plus size={16} /> Register seller</button>
    </div>
    <LoadState remote={remote}>
      {shown.length ? <div className="sellers-grid">{shown.map(seller => (
        <SellerCard
          key={seller.id}
          seller={seller}
          onReview={() => setReview(seller)}
          onNote={(action) => setNote({ seller, action })}
          onReinstate={() => patch(seller.id, { action: 'reinstate' }, 'Seller reinstated. Their listings are live again.').catch(e => notify(e.message))}
        />
      ))}</div> : <Empty title="Nobody here yet" text={filter === 'PENDING' ? 'Seller applications from the app will appear here for review.' : 'No sellers with this status yet.'} />}
    </LoadState>
    {review && <ApproveModal seller={review} token={token} onClose={() => setReview(null)} onDone={message => { setReview(null); remote.reload(); notify(message); }} />}
    {note && <NoteModal note={note} token={token} onClose={() => setNote(null)} onDone={(message) => { setNote(null); remote.reload(); notify(message); }} />}
    {register && <RegisterSellerModal token={token} onClose={() => setRegister(false)} onDone={message => { setRegister(false); remote.reload(); notify(message); }} />}
  </>;
}

function SellerCard({ seller, onReview, onNote, onReinstate }) {
  const s = seller;
  const initials = (s.displayName || 'S').trim().split(/\s+/).slice(0, 2).map(p => p[0]?.toUpperCase() || '').join('');
  return <article className="seller-card">
    <div className="seller-card-top">
      <span className="seller-avatar">{initials}</span>
      <div className="seller-card-heading">
        <h3>{s.displayName}{s.businessName ? <small>{s.businessName}</small> : null}</h3>
        <p>{s.category} · {s.businessType === 'BUSINESS' ? 'Business' : 'Individual'}</p>
      </div>
      <Pill status={s.status} />
    </div>
    <dl className="seller-meta">
      <div><dt>Based in</dt><dd>{[s.city, s.country].filter(Boolean).join(', ')}</dd></div>
      <div><dt>Contact</dt><dd>{s.phone}{s.email ? <><br />{s.email}</> : null}</dd></div>
      <div><dt>Applied</dt><dd>{dateTime(s.createdAt)}</dd></div>
      <div><dt>Listings · Orders</dt><dd>{s._count?.products ?? 0} · {s._count?.orders ?? 0}</dd></div>
      {s.status === 'APPROVED' && <div><dt>Agreed commission</dt><dd className="seller-commission">{pct(s.commissionBps)}</dd></div>}
    </dl>
    {s.headline && <p className="seller-headline">“{s.headline}”</p>}
    {s.reviewNote && <p className="seller-review-note"><ClipboardCheck size={13} /> {s.reviewNote}</p>}
    <div className="seller-actions">
      {(s.status === 'PENDING' || s.status === 'REJECTED') && <button className="button primary small" onClick={onReview}><Check size={15} /> {s.status === 'PENDING' ? 'Review & approve' : 'Approve anyway'}</button>}
      {s.status === 'PENDING' && <button className="text-button danger-text" onClick={() => onNote('reject')}><X size={15} /> Reject</button>}
      {s.status === 'APPROVED' && <button className="text-button danger-text" onClick={() => onNote('suspend')}><ShieldOff size={15} /> Suspend</button>}
      {s.status === 'SUSPENDED' && <button className="button secondary small" onClick={onReinstate}><RotateCcw size={15} /> Reinstate</button>}
    </div>
  </article>;
}

function ApproveModal({ seller, token, onClose, onDone }) {
  const [commission, setCommission] = useState(((seller.commissionBps ?? 1000) / 100).toFixed(1));
  const [note, setNote] = useState('');
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);
  async function approve(e) {
    e.preventDefault(); setBusy(true); setError('');
    const bps = Math.round(Number(commission) * 100);
    if (!Number.isFinite(bps) || bps < 0 || bps > 5000) { setError('Commission must be between 0% and 50%.'); setBusy(false); return; }
    try {
      await request(`/admin/commerce/sellers/${seller.id}`, { token, method: 'PATCH', body: JSON.stringify({ action: 'approve', commissionBps: bps, ...(note.trim() ? { reviewNote: note.trim() } : {}) }) });
      onDone(`Seller approved with ${pct(bps)} commission. Their shop is live.`);
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <Modal title={`Approve ${seller.displayName}`} label="SELLER REVIEW" onClose={onClose} busy={busy}>
    <form className="modal-body invite-form ops-form" onSubmit={approve}>
      {seller.bio && <p className="seller-bio">{seller.bio}</p>}
      <p className="ops-form-intro">The commission is agreed now and applies to every marketplace order this seller fulfils. The seller sees the rate in their studio.</p>
      <label>Commission rate (%)<input type="number" min="0" max="50" step="0.5" required value={commission} onChange={e => setCommission(e.target.value)} /></label>
      <label>Note to seller (optional)<textarea rows={2} maxLength={500} value={note} onChange={e => setNote(e.target.value)} placeholder="e.g. Welcome aboard — stock your Omaha warehouse slot by Friday." /></label>
      {error && <div className="alert error-alert" role="alert">{error}</div>}
      <button className="button primary full-button" disabled={busy}><ShieldCheck size={16} /> Approve seller</button>
    </form>
  </Modal>;
}

function NoteModal({ note, token, onClose, onDone }) {
  const [text, setText] = useState('');
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const reject = note.action === 'reject';
  async function submit(e) {
    e.preventDefault(); setBusy(true); setError('');
    if (text.trim().length < 3) { setError('Add a short reason the seller can act on.'); setBusy(false); return; }
    try {
      await request(`/admin/commerce/sellers/${note.seller.id}`, { token, method: 'PATCH', body: JSON.stringify({ action: note.action, reviewNote: text.trim() }) });
      onDone(reject ? 'Application rejected — the seller sees your note.' : 'Seller suspended. Their listings are hidden from buyers.');
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <Modal title={reject ? `Reject ${note.seller.displayName}` : `Suspend ${note.seller.displayName}`} label="SELLER REVIEW" onClose={onClose} busy={busy}>
    <form className="modal-body invite-form ops-form" onSubmit={submit}>
      <p className="ops-form-intro">{reject ? 'Tell the applicant what is missing — they can update and resubmit.' : 'Suspended sellers keep their account but their listings disappear from the storefront. Active orders still complete.'}</p>
      <label>Reason (the seller sees this)<textarea rows={3} required maxLength={500} value={text} onChange={e => setText(e.target.value)} /></label>
      {error && <div className="alert error-alert" role="alert">{error}</div>}
      <button className="button primary full-button" disabled={busy}>{reject ? 'Reject application' : 'Suspend seller'}</button>
    </form>
  </Modal>;
}

function RegisterSellerModal({ token, onClose, onDone }) {
  const [customerId, setCustomerId] = useState('');
  const [form, setForm] = useState({ displayName: '', businessType: 'INDIVIDUAL', businessName: '', category: '', country: '', city: '', phone: '', commission: '10.0' });
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const field = key => e => setForm({ ...form, [key]: e.target.value });
  async function submit(e) {
    e.preventDefault(); setBusy(true); setError('');
    const bps = Math.round(Number(form.commission) * 100);
    if (!Number.isFinite(bps) || bps < 0 || bps > 5000) { setError('Commission must be between 0% and 50%.'); setBusy(false); return; }
    const payload = { customerId, commissionBps: bps, businessType: form.businessType, category: form.category.trim(), ...(form.displayName.trim() ? { displayName: form.displayName.trim() } : {}), ...(form.businessType === 'BUSINESS' ? { businessName: form.businessName.trim() } : {}), ...(form.country.trim() ? { country: form.country.trim() } : {}), ...(form.city.trim() ? { city: form.city.trim() } : {}), ...(form.phone.trim() ? { phone: form.phone.trim() } : {}) };
    try {
      await request('/admin/commerce/sellers', { token, method: 'POST', body: JSON.stringify(payload) });
      onDone('Seller registered. They can list products in the app right away.');
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  const valid = customerId && form.category.trim() && (form.businessType !== 'BUSINESS' || form.businessName.trim());
  return <Modal title="Register a seller" label="ADMIN ONBOARDING" onClose={onClose} busy={busy}>
    <form className="modal-body invite-form ops-form" onSubmit={submit}>
      <p className="ops-form-intro">Register an app account as a seller without waiting for the in-app application. The person needs a D2F customer account with app access.</p>
      <CustomerPicker token={token} value={customerId} onChange={setCustomerId} />
      <label>Shop name (defaults to their profile)<input maxLength={120} value={form.displayName} onChange={field('displayName')} placeholder="e.g. Mama Adjoa Spices" /></label>
      <div className="form-row"><label>Seller type<select value={form.businessType} onChange={field('businessType')}><option value="INDIVIDUAL">Individual</option><option value="BUSINESS">Business</option></select></label>
        {form.businessType === 'BUSINESS' && <label>Business name<input maxLength={160} value={form.businessName} onChange={field('businessName')} /></label>}</div>
      <label>Main category<input required maxLength={80} value={form.category} onChange={field('category')} placeholder="e.g. Spices & Food" /></label>
      <div className="form-row"><label>Country<input maxLength={80} value={form.country} onChange={field('country')} placeholder="Defaults to their profile" /></label><label>City<input maxLength={120} value={form.city} onChange={field('city')} placeholder="Defaults to their profile" /></label></div>
      <div className="form-row"><label>Contact phone<input maxLength={40} value={form.phone} onChange={field('phone')} placeholder="Defaults to their profile" /></label><label>Commission rate (%)<input type="number" min="0" max="50" step="0.5" required value={form.commission} onChange={field('commission')} /></label></div>
      {error && <div className="alert error-alert" role="alert">{error}</div>}
      <button className="button primary full-button" disabled={busy || !valid}><Store size={16} /> Register seller</button>
    </form>
  </Modal>;
}

// Commission report: merchandise volume and D2F earnings per seller.
export function CommissionPanel({ token, refreshKey }) {
  const [period, setPeriod] = useState('30');
  const from = period === 'all' ? '2000-01-01T00:00:00.000Z' : new Date(Date.now() - Number(period) * 86400000).toISOString();
  const remote = useRemote(`/admin/commerce/commissions?from=${encodeURIComponent(from)}`, token, refreshKey);
  const currencies = remote.data?.currencies || [];
  const sellers = remote.data?.sellers || [];
  return <section className="panel">
    <div className="panel-heading">
      <div><h2>Commission report</h2><p>Agreed rates, snapshotted per order. D2F catalog sales carry 0% commission and are excluded here.</p></div>
      <label className="commission-period">Period<select value={period} onChange={e => setPeriod(e.target.value)} aria-label="Report period">
        <option value="7">Last 7 days</option>
        <option value="30">Last 30 days</option>
        <option value="90">Last 90 days</option>
        <option value="365">Last 12 months</option>
        <option value="all">All time</option>
      </select></label>
    </div>
    <LoadState remote={remote}>
      {currencies.length ? <>
        <div className="commission-cards">
          {currencies.map(row => <div key={row.currency} className="commission-card">
            <small>{row.currency}</small>
            <b>{money(row.commissionMinor, row.currency)}</b>
            <span>commission on {row.orders} {row.orders === 1 ? 'order' : 'orders'}</span>
            <em>Merchandise {money(row.merchandiseMinor, row.currency)}</em>
          </div>)}
        </div>
        {sellers.length ? <div className="table-scroll"><table><thead><tr><th>SELLER</th><th>CURRENCY</th><th>ORDERS</th><th>MERCHANDISE</th><th>COMMISSION</th></tr></thead><tbody>{sellers.map(row => <tr key={`${row.sellerId}-${row.currency}`}><td>{row.displayName}</td><td>{row.currency}</td><td>{row.orders}</td><td>{money(row.merchandiseMinor, row.currency)}</td><td><b>{money(row.commissionMinor, row.currency)}</b></td></tr>)}</tbody></table></div> : <Empty title="No seller orders yet" text="When sellers fulfil app orders, their contribution shows up here." />}
      </> : <Empty title="Nothing to report yet" text="When sellers fulfil orders through the app, commission accrues here automatically." />}
    </LoadState>
  </section>;
}
