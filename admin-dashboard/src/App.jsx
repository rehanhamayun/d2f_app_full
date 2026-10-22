import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  ArrowDownRight,
  ArrowUpRight,
  Bell,
  Box,
  Building2,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CircleHelp,
  Clock3,
  Copy,
  Download,
  Globe2,
  LayoutDashboard,
  LogOut,
  Menu,
  PackageCheck,
  Search,
  Settings2,
  ShieldCheck,
  Truck,
  UserRound,
  UsersRound,
  X,
} from 'lucide-react';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import {
  clearSession,
  getApiBaseUrl,
  getSavedSession,
  request,
  setApiBaseUrl,
  signIn,
} from './api.js';

const NAV = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'shipments', label: 'Shipments', icon: Box },
  { id: 'customers', label: 'Customers', icon: UserRound },
  { id: 'team', label: 'Team & access', icon: UsersRound },
  { id: 'system', label: 'System health', icon: Activity },
];
const STATUS_COLORS = {
  REQUESTED: '#f2b544',
  RECEIVED: '#3868ef',
  PROCESSING: '#7958cc',
  IN_TRANSIT: '#19a89a',
  ARRIVED_LOME: '#39a2d9',
  READY_FOR_PICKUP: '#ef8050',
  DELIVERED: '#3c9a64',
};
const STATUS_LABELS = {
  REQUESTED: 'Requested',
  RECEIVED: 'Received',
  PROCESSING: 'Processing',
  IN_TRANSIT: 'In transit',
  ARRIVED_LOME: 'Arrived in Lomé',
  READY_FOR_PICKUP: 'Ready for pickup',
  DELIVERED: 'Delivered',
};
const TRANSITIONS = {
  REQUESTED: ['RECEIVED'],
  RECEIVED: ['PROCESSING', 'IN_TRANSIT'],
  PROCESSING: ['IN_TRANSIT', 'ARRIVED_LOME'],
  IN_TRANSIT: ['ARRIVED_LOME'],
  ARRIVED_LOME: ['READY_FOR_PICKUP'],
  READY_FOR_PICKUP: ['DELIVERED'],
  DELIVERED: [],
};
const PAGE_SIZE = 50;

function formatNumber(value) {
  return new Intl.NumberFormat().format(value || 0);
}

function RecentActivity({ events, audits }) {
  const [tab, setTab] = useState('shipments');
  const items = tab === 'shipments' ? events : audits;
  return (
    <>
      <div className="activity-tabs" role="tablist" aria-label="Recent activity type">
        <button role="tab" aria-selected={tab === 'shipments'} className={tab === 'shipments' ? 'activity-tab-active' : ''} onClick={() => setTab('shipments')}>Shipment updates</button>
        <button role="tab" aria-selected={tab === 'admin'} className={tab === 'admin' ? 'activity-tab-active' : ''} onClick={() => setTab('admin')}>Admin changes</button>
      </div>
      {items.length ? <div className="activity-list">{items.slice(0, 5).map((item) => tab === 'shipments' ? (
        <div className="activity-item" key={item.id}><span className="activity-dot" style={{ '--status-color': STATUS_COLORS[item.status] || '#788295' }}><PackageCheck size={14} /></span><div className="activity-copy"><b>{statusLabel(item.status)}</b><span>{item.parcel?.trackingId} · {item.parcel?.customer?.displayName || item.parcel?.recipientName}</span></div><time>{formatDate(item.createdAt)}</time></div>
      ) : (
        <div className="activity-item" key={item.id}><span className="activity-dot audit-dot"><ShieldCheck size={14} /></span><div className="activity-copy"><b>{item.action.replaceAll('_', ' ')}</b><span>{item.actorName || 'System'} · {item.detail || item.entity}</span></div><time>{formatDate(item.createdAt)}</time></div>
      ))}</div> : <EmptyState icon={tab === 'shipments' ? Activity : ShieldCheck} title={tab === 'shipments' ? 'No recent activity' : 'No recorded admin changes'} text={tab === 'shipments' ? 'Shipment events will show here.' : 'Administrative actions will be listed here.'} />}
    </>
  );
}

function formatDate(value, options = { month: 'short', day: 'numeric' }) {
  if (!value) return '—';
  return new Intl.DateTimeFormat(undefined, options).format(new Date(value));
}

function initials(name = '') {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join('');
}

function statusLabel(status) {
  return STATUS_LABELS[status] || status?.replaceAll('_', ' ') || 'Unknown';
}

function Login({ onSignedIn }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [apiUrl, setApiUrl] = useState(getApiBaseUrl());
  const [showApi, setShowApi] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit(event) {
    event.preventDefault();
    setError('');
    setBusy(true);
    try {
      setApiBaseUrl(apiUrl);
      const session = await signIn(email, password);
      onSignedIn(session);
    } catch (problem) {
      setError(problem.message || 'Unable to sign in.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-shell">
      <section className="login-visual">
        <div className="login-brand">
          <span className="brand-mark"><Globe2 size={22} /></span>
          <span>D2F<span className="brand-light">Global</span></span>
        </div>
        <div className="visual-copy">
          <span className="eyebrow light-eyebrow">OPERATIONS, IN SYNC</span>
          <h1>Every shipment.<br />One clear view.</h1>
          <p>Manage your shipping operation with clarity, from first scan to final delivery.</p>
        </div>
        <div className="visual-route" aria-hidden="true">
          <div className="route-node"><span>OMA</span><i /></div>
          <div className="route-dash" />
          <div className="route-plane">✈</div>
          <div className="route-dash" />
          <div className="route-node"><span>LOM</span><i /></div>
        </div>
        <div className="visual-meta"><span>OMAHA · USA</span><span>LOMÉ · TOGO</span></div>
        <div className="visual-sun" />
      </section>
      <section className="login-panel">
        <div className="login-top"><span className="eyebrow">D2F ADMIN PORTAL</span><span className="secure-note"><ShieldCheck size={15} /> Secure access</span></div>
        <div className="login-form-wrap">
          <div className="login-icon"><Building2 size={23} /></div>
          <h2>Welcome back</h2>
          <p className="muted">Sign in with your D2F administrator account.</p>
          <form onSubmit={submit} className="login-form">
            <label htmlFor="admin-email">Email address</label>
            <input id="admin-email" autoComplete="username" type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="admin@d2fshipping.com" required />
            <label htmlFor="admin-password">Password</label>
            <input id="admin-password" autoComplete="current-password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" required />
            {error && <div className="alert error-alert" role="alert">{error}</div>}
            <button className="button primary full-button" disabled={busy}>
              {busy ? <span className="spinner" /> : 'Sign in to dashboard'}
              {!busy && <ChevronRight size={18} />}
            </button>
          </form>
          <button className="text-button api-setting" type="button" onClick={() => setShowApi(!showApi)}>
            <Settings2 size={15} /> {showApi ? 'Hide connection settings' : 'Connection settings'}
          </button>
          {showApi && (
            <div className="api-setting-box">
              <label>Backend API origin</label>
              <input value={apiUrl} onChange={(event) => setApiUrl(event.target.value)} placeholder="https://api.example.com" />
              <small>The address is saved in this browser. Use HTTPS for deployed dashboards.</small>
            </div>
          )}
        </div>
        <div className="login-foot"><span>© {new Date().getFullYear()} D2F Global</span><span>Authorized administrators only</span></div>
      </section>
    </main>
  );
}

function Sidebar({ page, setPage, user, onLogout, open, setOpen }) {
  return (
    <>
      {open && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setOpen(false)} />}
      <aside className={`sidebar ${open ? 'sidebar-open' : ''}`}>
        <div className="side-brand">
          <span className="brand-mark"><Globe2 size={21} /></span>
          <span>D2F<span className="brand-light">Global</span></span>
          <button className="icon-button side-close" onClick={() => setOpen(false)} aria-label="Close menu"><X size={19} /></button>
        </div>
        <div className="workspace-chip"><span className="workspace-dot" /><span><small>WORKSPACE</small><b>D2F Shipping</b></span><ChevronDown size={15} /></div>
        <div className="nav-caption">WORKSPACE</div>
        <nav className="side-nav" aria-label="Admin dashboard">
          {NAV.map(({ id, label, icon: Icon }) => (
            <button key={id} className={`nav-link ${page === id ? 'nav-active' : ''}`} onClick={() => { setPage(id); setOpen(false); }}>
              <Icon size={18} strokeWidth={1.9} /><span>{label}</span>
              {id === 'shipments' && page === id && <span className="nav-active-dot" />}
            </button>
          ))}
        </nav>
        <div className="side-grow" />
        <div className="side-help"><span className="help-icon"><CircleHelp size={18} /></span><div><b>Need a hand?</b><small>Contact the D2F team</small></div><ChevronRight size={15} /></div>
        <div className="profile-card">
          <div className="avatar">{initials(user.fullName)}</div>
          <div className="profile-info"><b>{user.fullName}</b><small>Administrator</small></div>
          <button className="icon-button logout-button" onClick={onLogout} title="Sign out" aria-label="Sign out"><LogOut size={17} /></button>
        </div>
      </aside>
    </>
  );
}

function Header({ page, onMenu, user, onRefresh, refreshing }) {
  const current = NAV.find((item) => item.id === page);
  return (
    <header className="topbar">
      <div className="topbar-left">
        <button className="icon-button mobile-menu" onClick={onMenu} aria-label="Open navigation"><Menu size={21} /></button>
        <div className="breadcrumbs"><span>Workspace</span><ChevronRight size={14} /><b>{current?.label || 'Overview'}</b></div>
      </div>
      <div className="topbar-actions">
        <button className="icon-button refresh-button" onClick={onRefresh} disabled={refreshing} aria-label="Refresh dashboard" title="Refresh"><Activity size={18} className={refreshing ? 'spin' : ''} /></button>
        <div className="topbar-divider" />
        <div className="topbar-user"><div className="avatar small-avatar">{initials(user.fullName)}</div><span><b>{user.fullName}</b><small>Admin</small></span></div>
        <button className="icon-button logout-mobile" onClick={() => window.dispatchEvent(new Event('d2f-logout'))} aria-label="Sign out"><LogOut size={17} /></button>
      </div>
    </header>
  );
}

function PageHeading({ eyebrow, title, subtitle, children }) {
  return (
    <div className="page-heading">
      <div><span className="eyebrow">{eyebrow}</span><h1>{title}</h1><p>{subtitle}</p></div>
      {children && <div className="heading-actions">{children}</div>}
    </div>
  );
}

function MetricCard({ label, value, change, icon: Icon, tone, note }) {
  return (
    <article className="metric-card">
      <div className="metric-top"><span>{label}</span><span className={`metric-icon ${tone}`}><Icon size={19} /></span></div>
      <div className="metric-value">{formatNumber(value)}</div>
      <div className="metric-foot">
        {change != null ? <span className={`metric-change ${change >= 0 ? 'positive' : 'negative'}`}>{change >= 0 ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}{Math.abs(change)}%</span> : <span className="metric-neutral"><Activity size={13} /> Live</span>}
        <span>{note}</span>
      </div>
    </article>
  );
}

function StatusPill({ status }) {
  const color = STATUS_COLORS[status] || '#788295';
  return <span className="status-pill" style={{ '--status-color': color }}>{statusLabel(status)}</span>;
}

function CustomTooltip({ active, payload, label }) {
  if (!active || !payload?.length) return null;
  return <div className="chart-tooltip"><b>{formatDate(label, { month: 'short', day: 'numeric', year: 'numeric' })}</b><span><i />{payload[0].value} {payload[0].value === 1 ? 'shipment' : 'shipments'}</span></div>;
}

function Overview({ data, onPeriod, days, loading, onGo }) {
  const statuses = useMemo(() => Object.entries(data?.statusCounts || {}).map(([status, count]) => ({ status, count, color: STATUS_COLORS[status] || '#788295' })).filter((item) => item.count), [data]);
  const methodData = useMemo(() => Object.entries(data?.methodCounts || {}).map(([method, count]) => ({ method, count })), [data]);
  return (
    <>
      <PageHeading eyebrow="YOUR OPERATION, AT A GLANCE" title="Good day, administrator" subtitle="Here’s what’s happening across your shipping operation.">
        <label className="select-wrap period-select"><Clock3 size={15} /><select value={days} onChange={(event) => onPeriod(Number(event.target.value))}><option value={7}>Last 7 days</option><option value={30}>Last 30 days</option><option value={90}>Last 90 days</option></select><ChevronDown size={15} /></label>
        <button className="button secondary" onClick={() => onGo('shipments')}><PackageCheck size={16} /> View shipments</button>
      </PageHeading>
      {loading && !data ? <LoadingPanel label="Loading your operations overview…" /> : data && (
        <>
          <div className="metric-grid">
            <MetricCard label="Total shipments" value={data.totalParcels} note="all time" icon={Box} tone="blue" />
            <MetricCard label="New shipments" value={data.periodParcels} note={`in the last ${days} days`} icon={PackageCheck} tone="coral" />
            <MetricCard label="Customers" value={data.customerCount} note="registered profiles" icon={UserRound} tone="yellow" />
            <MetricCard label="Active accounts" value={data.activeUsers} note={`${formatNumber(data.totalUsers)} total team & customer accounts`} icon={UsersRound} tone="purple" />
          </div>
          <div className="analytics-grid">
            <section className="panel trend-panel">
              <div className="panel-heading"><div><h2>Shipment activity</h2><p>New shipment requests over time</p></div><span className="chart-legend"><i /> Shipments</span></div>
              <div className="trend-chart">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={data.parcelTrend} margin={{ top: 10, right: 8, left: -18, bottom: 0 }}>
                    <defs><linearGradient id="shipmentGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#ff533d" stopOpacity={0.18} /><stop offset="95%" stopColor="#ff533d" stopOpacity={0.01} /></linearGradient></defs>
                    <CartesianGrid vertical={false} stroke="#edf0f4" strokeDasharray="4 6" />
                    <XAxis dataKey="date" tickFormatter={(value) => formatDate(value, { month: 'short', day: 'numeric' })} tickLine={false} axisLine={false} minTickGap={26} tick={{ fill: '#8b93a2', fontSize: 11, fontFamily: 'Plus Jakarta Sans' }} />
                    <YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={{ fill: '#8b93a2', fontSize: 11, fontFamily: 'Plus Jakarta Sans' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Area type="monotone" dataKey="count" stroke="#ff533d" strokeWidth={2.8} fill="url(#shipmentGradient)" activeDot={{ r: 5, stroke: '#fff', strokeWidth: 3, fill: '#ff533d' }} />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
              <div className="chart-summary"><span><b>{formatNumber(data.periodParcels)}</b> requests in this period</span><span>{days}-day view</span></div>
            </section>
            <section className="panel status-panel">
              <div className="panel-heading"><div><h2>Shipment status</h2><p>Current portfolio distribution</p></div><button className="icon-button mini-more" onClick={() => onGo('shipments')} aria-label="View shipment statuses"><ChevronRight size={18} /></button></div>
              <div className="donut-area">
                {statuses.length ? <ResponsiveContainer width="100%" height="100%"><PieChart><Pie data={statuses} dataKey="count" nameKey="status" innerRadius="67%" outerRadius="88%" paddingAngle={3} stroke="none" cornerRadius={6}>{statuses.map((entry) => <Cell key={entry.status} fill={entry.color} />)}</Pie><Tooltip formatter={(value, _name, item) => [value, statusLabel(item.payload.status)]} contentStyle={{ borderRadius: 12, borderColor: '#eff1f4', fontFamily: 'Plus Jakarta Sans', fontSize: 12 }} /></PieChart></ResponsiveContainer> : <div className="empty-chart">No shipment records yet</div>}
                <div className="donut-total"><b>{formatNumber(data.totalParcels)}</b><small>shipments</small></div>
              </div>
              <div className="legend-list">{statuses.slice(0, 5).map((item) => <div key={item.status}><span><i style={{ background: item.color }} />{statusLabel(item.status)}</span><b>{formatNumber(item.count)}</b></div>)}{statuses.length > 5 && <button className="text-button" onClick={() => onGo('shipments')}>View all statuses</button>}</div>
            </section>
          </div>
          <div className="lower-grid">
            <section className="panel method-panel">
              <div className="panel-heading"><div><h2>Shipping methods</h2><p>Shipment volume by service</p></div><Truck size={18} className="subtle-icon" /></div>
              <div className="method-list">{methodData.length ? methodData.map((item) => {
                const total = Math.max(data.totalParcels, 1);
                const color = item.method === 'AIR' ? '#ff684f' : item.method === 'SEA' ? '#3974ed' : '#36a889';
                return <div className="method-row" key={item.method}><span className="method-name"><i style={{ background: color }} />{item.method}</span><span className="method-track"><i style={{ width: `${Math.min((item.count / total) * 100, 100)}%`, background: color }} /></span><b>{item.count}</b></div>;
              }) : <EmptyState icon={Truck} title="No method data yet" text="New shipments will appear here." />}</div>
            </section>
            <section className="panel recent-panel">
              <div className="panel-heading"><div><h2>Recent activity</h2><p>Latest recorded shipment updates</p></div><button className="text-button" onClick={() => onGo('shipments')}>All shipments <ChevronRight size={15} /></button></div>
              <RecentActivity events={data.recentEvents || []} audits={data.recentAudit || []} />
            </section>
          </div>
        </>
      )}
    </>
  );
}

function LoadingPanel({ label = 'Loading…' }) {
  return <div className="loading-panel"><span className="spinner dark-spinner" />{label}</div>;
}

function EmptyState({ icon: Icon, title, text }) {
  return <div className="empty-state"><span><Icon size={20} /></span><b>{title}</b><p>{text}</p></div>;
}

function SearchInput({ value, onChange, placeholder }) {
  return <label className="search-input"><Search size={17} /><input value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} /></label>;
}

function PageControls({ total, offset, limit, onPage }) {
  const first = total ? offset + 1 : 0;
  const last = Math.min(offset + limit, total);
  return (
    <div className="table-pagination">
      <span>Showing {formatNumber(first)}–{formatNumber(last)} of {formatNumber(total)}</span>
      <div>
        <button className="button secondary" disabled={offset === 0} onClick={() => onPage(Math.max(0, offset - limit))}>Previous</button>
        <button className="button secondary" disabled={offset + limit >= total} onClick={() => onPage(offset + limit)}>Next</button>
      </div>
    </div>
  );
}

function Shipments({ token, notify, refreshOverview, refreshKey }) {
  const [rows, setRows] = useState([]);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('ALL');
  const [offset, setOffset] = useState(0);
  const [total, setTotal] = useState(0);
  const [reloadCount, setReloadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState(null);
  const [detail, setDetail] = useState(null);
  const [busy, setBusy] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const query = new URLSearchParams();
      if (search.trim()) query.set('q', search.trim());
      if (status !== 'ALL') query.set('status', status);
      query.set('limit', String(PAGE_SIZE));
      query.set('offset', String(offset));
      const result = await request(`/admin/parcels?${query}`, { token });
      setRows(result.parcels);
      setTotal(result.total);
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setLoading(false);
    }
  }, [token, search, status, offset, notify]);

  useEffect(() => {
    const timer = setTimeout(load, 180);
    return () => clearTimeout(timer);
  }, [load, refreshKey, reloadCount]);

  async function openDetail(parcel) {
    setSelected(parcel);
    setDetail(null);
    try {
      setDetail(await request(`/parcels/${encodeURIComponent(parcel.id)}`, { token }));
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  async function updateStatus(nextStatus, note, location) {
    if (!detail) return;
    setBusy(true);
    try {
      await request(`/parcels/${encodeURIComponent(detail.id)}/events`, {
        token,
        method: 'POST',
        body: JSON.stringify({ status: nextStatus, note, location }),
      });
      notify(`Shipment moved to ${statusLabel(nextStatus)}.`);
      const updated = await request(`/parcels/${encodeURIComponent(detail.id)}`, { token });
      setDetail(updated);
      setSelected(updated);
      await load();
      refreshOverview();
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeading eyebrow="SHIPMENT OPERATIONS" title="Shipments" subtitle="Search records, review tracking history, and move shipments through approved status transitions.">
        <button className="button primary" onClick={() => setCreateOpen(true)}><PackageCheck size={16} /> Create shipment</button>
      </PageHeading>
      <section className="panel table-panel">
        <div className="table-toolbar"><SearchInput value={search} onChange={(value) => { setSearch(value); setOffset(0); }} placeholder="Search tracking ID, recipient, or customer…" /><label className="select-wrap filter-select"><select value={status} onChange={(event) => { setStatus(event.target.value); setOffset(0); }}><option value="ALL">All statuses</option>{Object.entries(STATUS_LABELS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select><ChevronDown size={15} /></label><button className="icon-button table-reload" onClick={load} title="Refresh shipments" aria-label="Refresh shipments"><Activity size={17} /></button></div>
        <div className="table-scroll"><table><thead><tr><th>TRACKING ID</th><th>CUSTOMER / RECIPIENT</th><th>ROUTE</th><th>METHOD</th><th>STATUS</th><th>CREATED</th><th /></tr></thead><tbody>
          {loading ? <tr><td colSpan="7"><LoadingPanel label="Loading shipments…" /></td></tr> : rows.length ? rows.map((parcel) => <tr key={parcel.id} className="clickable-row" onClick={() => openDetail(parcel)}><td><span className="tracking-code">{parcel.trackingId}</span></td><td><b>{parcel.customer?.displayName || 'Customer'}</b><small className="cell-sub">{parcel.recipientName}</small></td><td><span className="route-text">{parcel.origin} <span>→</span> {parcel.destination}</span></td><td><span className={`method-tag ${parcel.method?.toLowerCase()}`}>{parcel.method}</span></td><td><StatusPill status={parcel.status} /></td><td>{formatDate(parcel.createdAt)}</td><td><ChevronRight size={16} className="table-chevron" /></td></tr>) : <tr><td colSpan="7"><EmptyState icon={Box} title="No shipments found" text="Try changing the search or status filter." /></td></tr>}
        </tbody></table></div>
        <div className="table-foot"><span>Live operational records shared with the D2F app</span><PageControls total={total} offset={offset} limit={PAGE_SIZE} onPage={setOffset} /></div>
      </section>
      {selected && <ShipmentModal parcel={detail || selected} loading={!detail} busy={busy} onClose={() => { setSelected(null); setDetail(null); }} onUpdate={updateStatus} />}
      {createOpen && <ShipmentCreateModal token={token} notify={notify} onClose={() => setCreateOpen(false)} onCreated={(parcel) => {
        setCreateOpen(false);
        setSearch('');
        setStatus('ALL');
        setOffset(0);
        setReloadCount((value) => value + 1);
        notify(`Shipment ${parcel.trackingId} created and shared with the D2F app.`);
        refreshOverview();
      }} />}
    </>
  );
}

function ShipmentCreateModal({ token, notify, onClose, onCreated }) {
  const [customers, setCustomers] = useState([]);
  const [customerTotal, setCustomerTotal] = useState(0);
  const [customerQuery, setCustomerQuery] = useState('');
  const [customerId, setCustomerId] = useState('');
  const [customerLoading, setCustomerLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    recipientName: '',
    recipientPhone: '',
    recipientAddress: '',
    packageType: 'BOX',
    weightKg: '',
    origin: 'Omaha',
    destination: 'Lomé',
    method: 'AIR',
    notes: '',
  });

  useEffect(() => {
    let active = true;
    const timer = setTimeout(async () => {
      setCustomerLoading(true);
      try {
        const query = new URLSearchParams({ limit: String(PAGE_SIZE), offset: '0' });
        if (customerQuery.trim()) query.set('q', customerQuery.trim());
        const result = await request(`/admin/customers?${query}`, { token });
        if (active) {
          setCustomers(result.customers);
          setCustomerTotal(result.total);
        }
      } catch (error) {
        if (active) notify(error.message, 'error');
      } finally {
        if (active) setCustomerLoading(false);
      }
    }, 150);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [token, customerQuery, notify]);

  async function submit(event) {
    event.preventDefault();
    if (!customerId) {
      notify('Choose a customer profile before creating a shipment.', 'error');
      return;
    }
    setSaving(true);
    try {
      const parcel = await request('/parcels', {
        token,
        method: 'POST',
        body: JSON.stringify({
          customerId,
          ...form,
          weightKg: Number(form.weightKg),
        }),
      });
      onCreated(parcel);
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="create-shipment-title">
        <div className="modal-header">
          <div><span className="eyebrow">NEW OPERATIONAL RECORD</span><h2 id="create-shipment-title">Create a shipment</h2></div>
          <button className="icon-button" onClick={onClose} aria-label="Close shipment form"><X size={19} /></button>
        </div>
        <form className="modal-body invite-form" onSubmit={submit}>
          <label>Find customer profile<input autoFocus value={customerQuery} onChange={(event) => { setCustomerQuery(event.target.value); setCustomerId(''); }} placeholder="Search name, email, or phone…" /></label>
          <label>Customer<select required value={customerId} onChange={(event) => setCustomerId(event.target.value)} disabled={customerLoading || !customers.length}>
            <option value="">{customerLoading ? 'Loading customer profiles…' : customers.length ? 'Select a customer' : 'No matching customer profiles'}</option>
            {customers.map((customer) => <option key={customer.id} value={customer.id}>{customer.displayName}{customer.email ? ` · ${customer.email}` : ''}{customer.userId ? ' · App account' : ' · Staff profile'}</option>)}
          </select></label>
          {customerTotal > customers.length && <p className="muted">Showing {formatNumber(customers.length)} of {formatNumber(customerTotal)} matching profiles. Search to find another customer.</p>}
          <p className="muted">A linked app account can see this shipment in its customer workspace. Staff-only profiles remain in operations records.</p>
          <label>Recipient name<input required maxLength={120} value={form.recipientName} onChange={(event) => setForm({ ...form, recipientName: event.target.value })} /></label>
          <div className="form-row">
            <label>Recipient phone<input value={form.recipientPhone} onChange={(event) => setForm({ ...form, recipientPhone: event.target.value })} /></label>
            <label>Package type<select value={form.packageType} onChange={(event) => setForm({ ...form, packageType: event.target.value })}>{['BOX', 'BARREL', 'TV', 'APPLIANCE', 'FURNITURE', 'PALLET', 'VEHICLE', 'DOCUMENTS', 'OTHER'].map((type) => <option key={type}>{type}</option>)}</select></label>
          </div>
          <div className="form-row">
            <label>Weight (kg)<input type="number" min="0.01" max="10000" step="0.01" required value={form.weightKg} onChange={(event) => setForm({ ...form, weightKg: event.target.value })} /></label>
            <label>Shipping method<select value={form.method} onChange={(event) => setForm({ ...form, method: event.target.value })}><option value="AIR">Air</option><option value="SEA">Sea</option><option value="ROAD">Road</option></select></label>
          </div>
          <div className="form-row">
            <label>Origin<input required maxLength={120} value={form.origin} onChange={(event) => setForm({ ...form, origin: event.target.value })} /></label>
            <label>Destination<input required maxLength={120} value={form.destination} onChange={(event) => setForm({ ...form, destination: event.target.value })} /></label>
          </div>
          <label>Staff note (optional)<input maxLength={1000} value={form.notes} onChange={(event) => setForm({ ...form, notes: event.target.value })} /></label>
          <div className="alert info-alert"><ShieldCheck size={16} /> The shipment is saved to the shared D2F API and appears in staff operations.</div>
          <button className="button primary full-button" disabled={saving || customerLoading || !customerId}>{saving ? <span className="spinner" /> : <PackageCheck size={16} />} Create shipment</button>
        </form>
      </section>
    </div>
  );
}

function ShipmentModal({ parcel, loading, busy, onClose, onUpdate }) {
  const [next, setNext] = useState('');
  const [note, setNote] = useState('');
  const [location, setLocation] = useState('');
  useEffect(() => {
    setNext(TRANSITIONS[parcel.status]?.[0] || '');
  }, [parcel.id, parcel.status]);
  const available = TRANSITIONS[parcel.status] || [];
  return (
    <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section className="modal shipment-modal" role="dialog" aria-modal="true" aria-labelledby="shipment-title">
        <div className="modal-header"><div><span className="eyebrow">SHIPMENT RECORD</span><h2 id="shipment-title">{parcel.trackingId}</h2></div><button className="icon-button" onClick={onClose} aria-label="Close shipment details"><X size={19} /></button></div>
        {loading ? <LoadingPanel label="Loading tracking history…" /> : <div className="modal-body">
          <div className="detail-status"><span><small>CURRENT STATUS</small><StatusPill status={parcel.status} /></span><span><small>CREATED</small><b>{formatDate(parcel.createdAt, { year: 'numeric', month: 'long', day: 'numeric' })}</b></span></div>
          <div className="detail-grid"><div><small>Customer</small><b>{parcel.customer?.displayName || '—'}</b></div><div><small>Recipient</small><b>{parcel.recipientName}</b></div><div><small>Route</small><b>{parcel.origin} → {parcel.destination}</b></div><div><small>Package</small><b>{parcel.packageType} · {parcel.weightKg} kg</b></div></div>
          <h3 className="modal-section-title">Tracking history</h3>
          <div className="timeline">{parcel.events?.map((event) => <div className="timeline-item" key={event.id}><span className="timeline-dot" style={{ '--status-color': STATUS_COLORS[event.status] || '#788295' }} /><div><b>{statusLabel(event.status)}</b><span>{event.note || event.location || 'Status updated'}</span><small>{formatDate(event.createdAt, { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}{event.actor?.fullName ? ` · ${event.actor.fullName}` : ''}</small></div></div>)}</div>
          {available.length > 0 ? <form className="status-update-form" onSubmit={(event) => { event.preventDefault(); onUpdate(next, note, location); }}><h3 className="modal-section-title">Update shipment</h3><div className="form-row"><label>Move to<select value={next} onChange={(event) => setNext(event.target.value)}>{available.map((state) => <option key={state} value={state}>{statusLabel(state)}</option>)}</select></label><label>Location<input value={location} onChange={(event) => setLocation(event.target.value)} placeholder="e.g. Omaha Warehouse" /></label></div><label>Update note<input value={note} onChange={(event) => setNote(event.target.value)} placeholder="Add a short tracking update (optional)" /></label><button className="button primary" disabled={busy || !next}>{busy ? <span className="spinner" /> : <Check size={16} />} Save status update</button></form> : <div className="complete-note"><Check size={16} /> This shipment is marked delivered. No further status changes are available.</div>}
        </div>}
      </section>
    </div>
  );
}

function Customers({ token, notify, refreshKey }) {
  const [customers, setCustomers] = useState([]);
  const [search, setSearch] = useState('');
  const [offset, setOffset] = useState(0);
  const [total, setTotal] = useState(0);
  const [reloadCount, setReloadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [addOpen, setAddOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({ displayName: '', email: '', phone: '', address: '', city: '', country: '' });
  useEffect(() => {
    let active = true;
    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const params = new URLSearchParams();
        if (search.trim()) params.set('q', search.trim());
        params.set('limit', String(PAGE_SIZE));
        params.set('offset', String(offset));
        const result = await request(`/admin/customers?${params}`, { token });
        if (active) {
          setCustomers(result.customers);
          setTotal(result.total);
        }
      } catch (error) {
        if (active) notify(error.message, 'error');
      } finally {
        if (active) setLoading(false);
      }
    }, 180);
    return () => { active = false; clearTimeout(timer); };
  }, [token, search, offset, notify, refreshKey, reloadCount]);
  async function addCustomer(event) {
    event.preventDefault();
    setSaving(true);
    try {
      const created = await request('/customers', {
        token,
        method: 'POST',
        body: JSON.stringify(Object.fromEntries(Object.entries(form).map(([key, value]) => [key, value.trim()]))),
      });
      setAddOpen(false);
      setForm({ displayName: '', email: '', phone: '', address: '', city: '', country: '' });
      notify('Customer profile added.');
      setOffset(0);
      setReloadCount((value) => value + 1);
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setSaving(false);
    }
  }
  return (
    <>
      <PageHeading eyebrow="CUSTOMER DIRECTORY" title="Customers" subtitle="Search and add customer profiles used by the shipping operation.">
        <button className="button primary" onClick={() => setAddOpen(true)}><UserRound size={16} /> Add customer</button>
      </PageHeading>
      <section className="panel table-panel">
        <div className="table-toolbar"><SearchInput value={search} onChange={(value) => { setSearch(value); setOffset(0); }} placeholder="Search name, email, or phone…" /><span className="toolbar-count">{formatNumber(total)} customers</span></div>
        <div className="table-scroll"><table><thead><tr><th>CUSTOMER</th><th>CONTACT</th><th>ADDRESS</th><th>ADDED</th></tr></thead><tbody>
          {loading ? <tr><td colSpan="4"><LoadingPanel label="Loading customers…" /></td></tr> : customers.length ? customers.map((customer) => <tr key={customer.id}><td><span className="customer-cell"><span className="avatar customer-avatar">{initials(customer.displayName)}</span><span className="user-cell-info"><b>{customer.displayName}</b><small>{customer.userId ? 'Customer app account linked' : 'Staff profile only'}</small></span></span></td><td><b>{customer.email || '—'}</b><small className="cell-sub">{customer.phone || 'No phone provided'}</small></td><td><span className="address-cell">{[customer.address, customer.city, customer.country].filter(Boolean).join(', ') || '—'}</span></td><td>{formatDate(customer.createdAt)}</td></tr>) : <tr><td colSpan="4"><EmptyState icon={UserRound} title="No customers found" text="Customers appear here when added to the shipping records." /></td></tr>}
        </tbody></table></div>
        <div className="table-foot"><span>Customer profiles shared with D2F shipping operations</span><PageControls total={total} offset={offset} limit={PAGE_SIZE} onPage={setOffset} /></div>
      </section>
      {addOpen && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setAddOpen(false); }}><section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="customer-title"><div className="modal-header"><div><span className="eyebrow">CUSTOMER RECORD</span><h2 id="customer-title">Add a customer</h2></div><button className="icon-button" onClick={() => setAddOpen(false)} aria-label="Close customer form"><X size={19} /></button></div><form className="modal-body invite-form" onSubmit={addCustomer}><label>Full name<input autoFocus required maxLength={120} value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} placeholder="Customer name" /></label><div className="form-row"><label>Email address<input type="email" value={form.email} onChange={(event) => setForm({ ...form, email: event.target.value })} placeholder="name@example.com" /></label><label>Phone<input value={form.phone} onChange={(event) => setForm({ ...form, phone: event.target.value })} placeholder="+1 402 555 0100" /></label></div><label>Street address<input value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} placeholder="Address (optional)" /></label><div className="form-row"><label>City<input value={form.city} onChange={(event) => setForm({ ...form, city: event.target.value })} placeholder="City" /></label><label>Country<input value={form.country} onChange={(event) => setForm({ ...form, country: event.target.value })} placeholder="Country" /></label></div><div className="alert info-alert"><ShieldCheck size={16} /> This creates a shipping profile; it does not create an app login account.</div><button className="button primary full-button" disabled={saving}>{saving ? <span className="spinner" /> : <Check size={16} />} Save customer profile</button></form></section></div>}
    </>
  );
}

function Team({ token, notify, refreshKey, currentUserId }) {
  const [users, setUsers] = useState([]);
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('ALL');
  const [offset, setOffset] = useState(0);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState('');
  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteRole, setInviteRole] = useState('STAFF');
  const [inviteEmail, setInviteEmail] = useState('');
  const [invite, setInvite] = useState(null);
  const [inviteBusy, setInviteBusy] = useState(false);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const query = new URLSearchParams();
      if (search.trim()) query.set('q', search.trim());
      if (role !== 'ALL') query.set('role', role);
      query.set('limit', String(PAGE_SIZE));
      query.set('offset', String(offset));
      const result = await request(`/admin/users?${query}`, { token });
      setUsers(result.users);
      setTotal(result.total);
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setLoading(false);
    }
  }, [token, search, role, offset, notify]);
  useEffect(() => {
    const timer = setTimeout(load, 180);
    return () => clearTimeout(timer);
  }, [load, refreshKey]);

  async function toggleActive(user) {
    const action = user.isActive ? 'deactivate' : 'reactivate';
    if (!window.confirm(`Are you sure you want to ${action} ${user.fullName}?`)) return;
    setPending(user.id);
    try {
      const result = await request(`/admin/users/${encodeURIComponent(user.id)}/active`, {
        token,
        method: 'PATCH',
        body: JSON.stringify({ isActive: !user.isActive }),
      });
      setUsers((existing) => existing.map((item) => item.id === user.id ? result.user : item));
      notify(`${user.fullName} ${user.isActive ? 'deactivated' : 'reactivated'}.`);
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setPending('');
    }
  }

  async function createInvite(event) {
    event.preventDefault();
    setInviteBusy(true);
    try {
      const result = await request('/auth/invitations', {
        token,
        method: 'POST',
        body: JSON.stringify({ email: inviteEmail.trim(), role: inviteRole }),
      });
      setInvite({ ...result, email: inviteEmail.trim(), role: inviteRole });
      notify('Invitation created. Share it securely with the intended teammate.');
      await load();
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setInviteBusy(false);
    }
  }

  async function copyInvite() {
    try {
      await navigator.clipboard.writeText(invite.invitation);
      notify('Invitation code copied.');
    } catch {
      notify('Clipboard access is blocked. Select and copy the invitation code.', 'error');
    }
  }

  return (
    <>
      <PageHeading eyebrow="PEOPLE & PERMISSIONS" title="Team & access" subtitle="Review account roles and invite trusted staff or drivers." >
        <button className="button primary" onClick={() => { setInvite(null); setInviteOpen(true); }}><UsersRound size={16} /> Create invitation</button>
      </PageHeading>
      <section className="panel table-panel">
        <div className="table-toolbar"><SearchInput value={search} onChange={(value) => { setSearch(value); setOffset(0); }} placeholder="Search by name or email…" /><label className="select-wrap filter-select"><select value={role} onChange={(event) => { setRole(event.target.value); setOffset(0); }}><option value="ALL">All roles</option><option value="ADMIN">Admin</option><option value="STAFF">Staff</option><option value="DRIVER">Driver</option><option value="CUSTOMER">Customer</option></select><ChevronDown size={15} /></label></div>
        <div className="table-scroll"><table><thead><tr><th>ACCOUNT</th><th>ROLE</th><th>LOCATION</th><th>JOINED</th><th>ACCESS</th><th /></tr></thead><tbody>
          {loading ? <tr><td colSpan="6"><LoadingPanel label="Loading accounts…" /></td></tr> : users.length ? users.map((user) => <tr key={user.id}><td><span className="customer-cell"><span className="avatar customer-avatar">{initials(user.fullName)}</span><span className="user-cell-info"><b>{user.fullName}</b><small>{user.email}</small></span></span></td><td><span className={`role-tag ${user.role.toLowerCase()}`}>{user.role}</span></td><td>{user.location?.name || '—'}</td><td>{formatDate(user.createdAt)}</td><td><span className={`access-indicator ${user.isActive ? 'enabled' : 'disabled'}`}><i />{user.isActive ? 'Active' : 'Disabled'}</span></td><td>{user.id !== currentUserId && <button className={`text-button account-action ${user.isActive ? 'danger-text' : ''}`} disabled={pending === user.id} onClick={() => toggleActive(user)}>{pending === user.id ? 'Saving…' : user.isActive ? 'Disable' : 'Reactivate'}</button>}</td></tr>) : <tr><td colSpan="6"><EmptyState icon={UsersRound} title="No matching accounts" text="Try a different role or search term." /></td></tr>}
        </tbody></table></div>
        <div className="table-foot"><span>Roles and access are enforced by the backend</span><PageControls total={total} offset={offset} limit={PAGE_SIZE} onPage={setOffset} /></div>
      </section>
      {inviteOpen && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setInviteOpen(false); }}><section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="invite-title"><div className="modal-header"><div><span className="eyebrow">SECURE TEAM ONBOARDING</span><h2 id="invite-title">{invite ? 'Invitation ready' : 'Invite a teammate'}</h2></div><button className="icon-button" onClick={() => setInviteOpen(false)} aria-label="Close invitation"><X size={19} /></button></div>{invite ? <div className="modal-body"><div className="invite-success"><span><Check size={20} /></span><div><b>{invite.role} invitation created</b><small>For {invite.email} · expires in {invite.expiresInDays} days</small></div></div><label className="invite-code-label">ONE-TIME SIGNUP CODE</label><div className="invite-code"><code>{invite.invitation}</code><button className="button secondary" onClick={copyInvite}><Copy size={15} /> Copy</button></div><div className="alert warning-alert">This code grants {invite.role.toLowerCase()} access. Send it only to {invite.email} through a private channel. The invitee must sign up with that exact email.</div><button className="button primary full-button" onClick={() => setInviteOpen(false)}>Done</button></div> : <form className="modal-body invite-form" onSubmit={createInvite}><p className="muted">Invitations are restricted to Staff or Driver and are bound to the recipient’s email address.</p><label>Email address<input autoFocus type="email" required value={inviteEmail} onChange={(event) => setInviteEmail(event.target.value)} placeholder="teammate@example.com" /></label><label>Role<select value={inviteRole} onChange={(event) => setInviteRole(event.target.value)}><option value="STAFF">Staff · shipping operations</option><option value="DRIVER">Driver · delivery workflow</option></select></label><div className="alert info-alert"><ShieldCheck size={16} /> Admin access cannot be granted through public invitations.</div><button className="button primary full-button" disabled={inviteBusy}>{inviteBusy ? <span className="spinner" /> : <UsersRound size={16} />} Generate secure invitation</button></form>}</section></div>}
    </>
  );
}

function SystemHealth({ token, notify, refreshKey }) {
  const [health, setHealth] = useState(null);
  const [loading, setLoading] = useState(true);
  const [apiUrl, setApiUrl] = useState(getApiBaseUrl());
  const [saving, setSaving] = useState(false);
  const check = useCallback(async () => {
    setLoading(true);
    try {
      const result = await request('/health', { token });
      setHealth({ ok: true, ...result, checkedAt: new Date().toISOString() });
    } catch (error) {
      setHealth({ ok: false, error: error.message, checkedAt: new Date().toISOString() });
    } finally {
      setLoading(false);
    }
  }, [token]);
  useEffect(() => { check(); }, [check, refreshKey]);
  function saveUrl(event) {
    event.preventDefault();
    try {
      setSaving(true);
      const url = setApiBaseUrl(apiUrl);
      setApiUrl(url);
      notify('API origin saved in this browser.');
      check();
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setSaving(false);
    }
  }
  return (
    <>
      <PageHeading eyebrow="SERVICE STATUS" title="System health" subtitle="Check the API/database connection and configure this browser’s API origin." ><button className="button secondary" onClick={check}><Activity size={16} /> Check now</button></PageHeading>
      <div className="health-grid"><section className="panel health-card"><div className={`health-mark ${health?.ok ? 'health-ok' : health ? 'health-error' : ''}`}>{loading ? <span className="spinner dark-spinner" /> : health?.ok ? <Check size={24} /> : <X size={24} />}</div><div><span className="eyebrow">D2F API & DATABASE</span><h2>{loading ? 'Checking connection…' : health?.ok ? 'Services responding' : 'Connection unavailable'}</h2><p>{health?.ok ? `API: ${health.service} · Database: ${health.database}` : health?.error || 'Waiting for the health check.'}</p>{health?.checkedAt && <small>Last checked {formatDate(health.checkedAt, { hour: 'numeric', minute: '2-digit', second: '2-digit' })}</small>}</div><span className={`health-status ${health?.ok ? 'online' : health ? 'offline' : 'checking'}`}><i />{loading ? 'Checking' : health?.ok ? 'Operational' : 'Unavailable'}</span></section><section className="panel settings-card"><div className="panel-heading"><div><h2>API connection</h2><p>Change the backend used by this dashboard in this browser.</p></div><Settings2 size={19} className="subtle-icon" /></div><form className="api-form" onSubmit={saveUrl}><label>Backend API origin<input value={apiUrl} onChange={(event) => setApiUrl(event.target.value)} placeholder="https://api.example.com" /></label><div className="alert info-alert"><ShieldCheck size={16} /> Use HTTPS for production. Changing this setting takes effect for dashboard requests immediately.</div><button className="button primary" disabled={saving}>{saving ? <span className="spinner" /> : <Check size={16} />} Save API origin</button></form></section></div>
      <section className="panel security-note-panel"><span className="security-note-icon"><ShieldCheck size={20} /></span><div><b>Admin access is enforced server-side</b><p>Dashboard sections use authenticated API routes. The dashboard hides account credentials and stores its session only in this browser tab.</p></div></section>
    </>
  );
}

function Toast({ toast, onClose }) {
  useEffect(() => {
    if (!toast) return undefined;
    const timer = setTimeout(onClose, 4400);
    return () => clearTimeout(timer);
  }, [toast, onClose]);
  if (!toast) return null;
  return <div className={`toast ${toast.type === 'error' ? 'toast-error' : ''}`} role="status"><span>{toast.type === 'error' ? <X size={16} /> : <Check size={16} />}</span>{toast.message}<button onClick={onClose} aria-label="Dismiss message"><X size={15} /></button></div>;
}

export default function App() {
  const [session, setSession] = useState(getSavedSession);
  const [page, setPage] = useState('overview');
  const [days, setDays] = useState(30);
  const [overview, setOverview] = useState(null);
  const [overviewLoading, setOverviewLoading] = useState(false);
  const [toast, setToast] = useState(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const notify = useCallback((message, type = 'success') => setToast({ message, type, key: Date.now() }), []);
  const token = session?.token;

  const loadOverview = useCallback(async () => {
    if (!token) return;
    setOverviewLoading(true);
    try {
      setOverview(await request(`/admin/overview?days=${days}`, { token }));
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setOverviewLoading(false);
    }
  }, [token, days, notify]);

  useEffect(() => {
    if (token) loadOverview();
  }, [token, loadOverview]);

  useEffect(() => {
    const logout = () => {
      clearSession();
      setSession(null);
      setOverview(null);
      setPage('overview');
    };
    const expired = () => {
      logout();
      setToast({ message: 'Your session expired. Please sign in again.', type: 'error', key: Date.now() });
    };
    window.addEventListener('d2f-logout', logout);
    window.addEventListener('d2f-session-expired', expired);
    return () => {
      window.removeEventListener('d2f-logout', logout);
      window.removeEventListener('d2f-session-expired', expired);
    };
  }, []);

  async function verifySession(saved) {
    try {
      const result = await request('/auth/me', { token: saved.token });
      if (result.user?.role !== 'ADMIN') throw new Error('This account no longer has Admin access.');
      setSession({ ...saved, user: result.user });
    } catch {
      clearSession();
      setSession(null);
    }
  }

  useEffect(() => {
    const saved = getSavedSession();
    if (saved) verifySession(saved);
  }, []);

  const refreshing = overviewLoading;
  return session ? (
    <div className="app-shell">
      <Sidebar page={page} setPage={setPage} user={session.user} onLogout={() => window.dispatchEvent(new Event('d2f-logout'))} open={menuOpen} setOpen={setMenuOpen} />
      <div className="main-shell">
        <Header page={page} onMenu={() => setMenuOpen(true)} user={session.user} onRefresh={page === 'overview' ? loadOverview : () => setRefreshKey((value) => value + 1)} refreshing={refreshing} />
        <main className="content">
          {page === 'overview' && <Overview data={overview} days={days} onPeriod={setDays} loading={overviewLoading} onGo={setPage} />}
          {page === 'shipments' && <Shipments token={token} notify={notify} refreshOverview={loadOverview} refreshKey={refreshKey} key="shipments" />}
          {page === 'customers' && <Customers token={token} notify={notify} refreshKey={refreshKey} key="customers" />}
          {page === 'team' && <Team token={token} notify={notify} refreshKey={refreshKey} currentUserId={session.user.id} key="team" />}
          {page === 'system' && <SystemHealth token={token} notify={notify} refreshKey={refreshKey} key="system" />}
          <footer className="page-footer"><span>© {new Date().getFullYear()} D2F Global</span><span><ShieldCheck size={13} /> Admin operations · Data from D2F API</span></footer>
        </main>
      </div>
      <Toast toast={toast} onClose={() => setToast(null)} />
    </div>
  ) : (
    <>
      <Login onSignedIn={(value) => { setSession(value); setToast({ message: 'Welcome to your Admin dashboard.', type: 'success', key: Date.now() }); }} />
      <Toast toast={toast} onClose={() => setToast(null)} />
    </>
  );
}
