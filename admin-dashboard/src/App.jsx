import { CustodyActions } from './custody.jsx';
import { ConnectOperations, AirCargoReference } from './connect.jsx';
import { UserLocation } from './team-location.jsx';
import { Containers, Locations } from './warehouse.jsx';
import { Commerce } from './commerce.jsx';
import { SERVICE_COUNTRIES, ROUTE_LOCATIONS } from './service-area.js';
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
  KeyRound,
  LayoutDashboard,
  LogOut,
  Menu,
  PackageCheck,
  Pencil,
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
  saveSession,
  setApiBaseUrl,
  signIn,
} from './api.js';

const NAV = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'shipments', label: 'Shipments', icon: Box },
  { id: 'connect', label: 'D2F Connect', icon: Globe2 },
  { id: 'containers', label: 'Containers', icon: PackageCheck },
  { id: 'bookings', label: 'Bookings', icon: Truck },
  { id: 'locations', label: 'Locations', icon: Globe2 },
  { id: 'marketplace', label: 'Marketplace', icon: Building2 },
  { id: 'buy-for-me', label: 'Buy For Me', icon: Download },
  { id: 'customers', label: 'Customers', icon: UserRound },
  { id: 'team', label: 'Team & access', icon: UsersRound },
  { id: 'system', label: 'System health', icon: Activity },
];
const STATUS_COLORS = {
  REQUESTED: '#f2b544',
  PICKUP_SCHEDULED: '#4a7cfa',
  PICKED_UP: '#9b6cde',
  RECEIVED: '#3868ef',
  PROCESSING: '#7958cc',
  IN_TRANSIT: '#19a89a',
  ARRIVED_LOME: '#39a2d9',
  ARRIVED_DESTINATION: '#39a2d9',
  RELEASED: '#159553',
  READY_FOR_PICKUP: '#ef8050',
  DELIVERED: '#3c9a64',
};
const STATUS_LABELS = {
  REQUESTED: 'Requested',
  PICKUP_SCHEDULED: 'Pickup scheduled',
  PICKED_UP: 'Pickup confirmed · driver custody',
  RECEIVED: 'Received at Warehouse',
  PROCESSING: 'Processing',
  IN_TRANSIT: 'In transit',
  ARRIVED_LOME: 'Arrived in Lomé',
  ARRIVED_DESTINATION: 'Arrived at destination',
  RELEASED: 'Released',
  READY_FOR_PICKUP: 'Ready for pickup',
  OUT_FOR_DELIVERY: 'Out for Delivery',
  DELIVERED: 'Delivered',
};
const TRANSITIONS = {
  REQUESTED: ['RECEIVED', 'PICKUP_SCHEDULED'],
  PICKUP_SCHEDULED: ['PICKED_UP'],
  PICKED_UP: ['RECEIVED'],
  RECEIVED: ['PROCESSING'],
  PROCESSING: ['IN_TRANSIT'],
  IN_TRANSIT: ['ARRIVED_LOME', 'ARRIVED_DESTINATION'],
  ARRIVED_LOME: ['READY_FOR_PICKUP', 'OUT_FOR_DELIVERY'],
  ARRIVED_DESTINATION: ['READY_FOR_PICKUP', 'OUT_FOR_DELIVERY'],
  READY_FOR_PICKUP: ['DELIVERED', 'OUT_FOR_DELIVERY', 'RELEASED'],
  OUT_FOR_DELIVERY: ['DELIVERED'],
  RELEASED: ['DELIVERED'],
  DELIVERED: [],
};
// Stage names that only exist when D2F collects the goods; a drop-off
// shipment goes straight from REQUESTED to RECEIVED at the warehouse.
const PICKUP_ONLY_STATUSES = new Set(['PICKUP_SCHEDULED', 'PICKED_UP']);
const CONFIRMATION_STATUSES = new Set(['RECEIVED', 'IN_TRANSIT', 'ARRIVED_LOME', 'ARRIVED_DESTINATION', 'READY_FOR_PICKUP', 'RELEASED', 'DELIVERED']);
const FACILITY_REQUIRED_STATUSES = new Set([...CONFIRMATION_STATUSES, 'PROCESSING']);
const DELIVERY_PROOF_TYPES = {
  SIGNATURE: 'Signature',
  PHOTO: 'Photo',
  ID_CONFIRMATION: 'ID confirmation',
  RECIPIENT_CONFIRMATION: 'Recipient confirmation',
};
const PAGE_SIZE = 50;

function localInputValue(date = new Date()) {
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function routeCity(value = '') {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .split(',')[0]
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function sameCity(a, b) {
  const left = routeCity(a);
  const right = routeCity(b);
  return Boolean(left && right && left === right);
}

function routeError({ origin, destination, method, pickupAddress, recipientAddress }) {
  if (!sameCity(origin, destination)) return '';
  if (method === 'ROAD') {
    if (!pickupAddress?.trim() || !recipientAddress?.trim()) return 'Same-city road deliveries require both a pickup address and a delivery address.';
    const fold = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    if (fold(pickupAddress) === fold(recipientAddress)) return 'Pickup and delivery addresses must be different for a same-city road delivery.';
    return '';
  }
  return 'Air and sea shipments require different origin and destination cities.';
}

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
  const [notice, setNotice] = useState('');
  const [mode, setMode] = useState('login');
  const [ticket, setTicket] = useState('');
  const [code, setCode] = useState('');
  const [newPassword, setNewPassword] = useState('');

  async function submit(event) {
    event.preventDefault();
    setError('');
    setNotice('');
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

  async function requestRecovery(event) {
    event.preventDefault();
    setError('');
    setNotice('');
    setBusy(true);
    try {
      setApiBaseUrl(apiUrl);
      const result = await request('/auth/password/forgot', {
        method: 'POST',
        body: JSON.stringify({ email: email.trim() }),
      });
      setTicket(result.ticket);
      setMode('reset');
      setNotice('If an active account matches this email, a 6-digit code has been sent. It expires in 10 minutes.');
    } catch (problem) {
      setError(problem.message || 'Unable to start password recovery.');
    } finally {
      setBusy(false);
    }
  }

  async function completeRecovery(event) {
    event.preventDefault();
    setError('');
    setNotice('');
    setBusy(true);
    try {
      setApiBaseUrl(apiUrl);
      await request('/auth/password/reset', {
        method: 'POST',
        body: JSON.stringify({ ticket, code: code.trim(), password: newPassword }),
      });
      setMode('login');
      setPassword('');
      setCode('');
      setNewPassword('');
      setNotice('Password updated. Sign in with your new password.');
    } catch (problem) {
      setError(problem.message || 'Unable to reset the password.');
    } finally {
      setBusy(false);
    }
  }

  function backToLogin() {
    setMode('login');
    setError('');
    setNotice('');
    setCode('');
    setNewPassword('');
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
          <h2>{mode === 'login' ? 'Welcome back' : mode === 'recover' ? 'Reset your password' : 'Enter your code'}</h2>
          <p className="muted">
            {mode === 'login'
              ? 'Sign in with your authorized D2F operations account.'
              : mode === 'recover'
                ? 'We will email a 6-digit code to your account address.'
                : 'Enter the code from your email and choose a new password.'}
          </p>
          {notice && <div className="alert info-alert" role="status">{notice}</div>}
          {mode === 'login' && (
            <>
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
              <button className="text-button api-setting" type="button" onClick={() => { setMode('recover'); setError(''); setNotice(''); }}>
                <ShieldCheck size={15} /> Forgot password?
              </button>
            </>
          )}
          {mode === 'recover' && (
            <form onSubmit={requestRecovery} className="login-form">
              <label htmlFor="recover-email">Email address</label>
              <input id="recover-email" autoComplete="username" type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="admin@d2fshipping.com" required />
              {error && <div className="alert error-alert" role="alert">{error}</div>}
              <button className="button primary full-button" disabled={busy}>{busy ? <span className="spinner" /> : 'Send recovery code'}</button>
              <button className="text-button" type="button" onClick={backToLogin}>Back to sign in</button>
            </form>
          )}
          {mode === 'reset' && (
            <form onSubmit={completeRecovery} className="login-form">
              <label htmlFor="recover-code">6-digit code</label>
              <input id="recover-code" inputMode="numeric" pattern="\d{6}" maxLength={6} autoComplete="one-time-code" value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, ''))} placeholder="000000" required />
              <label htmlFor="recover-password">New password</label>
              <input id="recover-password" autoComplete="new-password" type="password" minLength={8} value={newPassword} onChange={(event) => setNewPassword(event.target.value)} placeholder="At least 8 characters" required />
              {error && <div className="alert error-alert" role="alert">{error}</div>}
              <button className="button primary full-button" disabled={busy}>{busy ? <span className="spinner" /> : 'Set new password'}</button>
              <button className="text-button" type="button" onClick={backToLogin}>Back to sign in</button>
            </form>
          )}
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
        <div className="login-foot"><span>© {new Date().getFullYear()} D2F Global</span><span>Authorized Admin and Staff accounts</span></div>
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
          {NAV.filter(item => user.role === 'ADMIN' || ['shipments', 'connect', 'containers', 'bookings', 'customers'].includes(item.id)).map(({ id, label, icon: Icon }) => (
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
          <div className="profile-info"><b>{user.fullName}</b><small>{user.role === 'ADMIN' ? 'Administrator' : 'Dispatcher / Staff'}</small></div>
          <button className="icon-button logout-button" onClick={onLogout} title="Sign out" aria-label="Sign out"><LogOut size={17} /></button>
        </div>
      </aside>
    </>
  );
}

function Header({ page, onMenu, user, onRefresh, refreshing, onChangePassword }) {
  const current = NAV.find((item) => item.id === page);
  return (
    <header className="topbar">
      <div className="topbar-left">
        <button className="icon-button mobile-menu" onClick={onMenu} aria-label="Open navigation"><Menu size={21} /></button>
        <div className="breadcrumbs"><span>Workspace</span><ChevronRight size={14} /><b>{current?.label || 'Overview'}</b></div>
      </div>
      <div className="topbar-actions">
        <button className="icon-button refresh-button" onClick={onRefresh} disabled={refreshing} aria-label="Refresh dashboard" title="Refresh"><Activity size={18} className={refreshing ? 'spin' : ''} /></button>
        <button className="icon-button" onClick={onChangePassword} aria-label="Change password" title="Change password"><KeyRound size={17} /></button>
        <div className="topbar-divider" />
        <div className="topbar-user"><div className="avatar small-avatar">{initials(user.fullName)}</div><span><b>{user.fullName}</b><small>{user.role === 'ADMIN' ? 'Admin' : 'Staff'}</small></span></div>
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

function Shipments({ token, notify, refreshOverview, refreshKey, bookings = false, staffAccess = false, currentUserId }) {
  const [rows, setRows] = useState([]);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState(bookings ? 'REQUESTED' : 'ALL');
  const [offset, setOffset] = useState(0);
  const [total, setTotal] = useState(0);
  const [reloadCount, setReloadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState(null);
  const [detail, setDetail] = useState(null);
  const [busy, setBusy] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const query = new URLSearchParams();
      if (search.trim()) query.set('q', search.trim());
      if (status !== 'ALL') query.set('status', status);
      query.set('limit', String(PAGE_SIZE));
      query.set('offset', String(offset));
      const result = await request(`${staffAccess ? '/warehouse/directory' : '/admin'}/parcels?${query}`, { token });
      setRows(result.parcels);
      setTotal(result.total);
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setLoading(false);
    }
  }, [token, search, status, offset, notify, staffAccess]);

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

  async function refreshDetail() {
    if (!detail) return;
    const updated = await request(`/parcels/${encodeURIComponent(detail.id)}`, { token });
    setDetail(updated);
    setSelected(updated);
  }

  async function updateStatus(payload) {
    if (!detail) return;
    setBusy(true);
    try {
      await request(`/parcels/${encodeURIComponent(detail.id)}/events`, {
        token,
        method: 'POST',
        body: JSON.stringify(payload),
      });
      notify(`Shipment moved to ${statusLabel(payload.status)}.`);
      await refreshDetail();
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
      <PageHeading eyebrow="SHIPMENT OPERATIONS" title={bookings ? "Bookings" : "Shipments"} subtitle={bookings ? "Review customer shipment requests and confirm warehouse intake." : "Search records, review tracking history, and move shipments through approved status transitions."}>
        <button className="button primary" onClick={() => setCreateOpen(true)}><PackageCheck size={16} /> Create shipment</button>
      </PageHeading>
      <section className="panel table-panel">
        <div className="table-toolbar"><SearchInput value={search} onChange={(value) => { setSearch(value); setOffset(0); }} placeholder="Search tracking ID, recipient, or customer…" /><label className="select-wrap filter-select"><select value={status} onChange={(event) => { setStatus(event.target.value); setOffset(0); }}><option value="ALL">All statuses</option>{Object.entries(STATUS_LABELS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select><ChevronDown size={15} /></label><button className="icon-button table-reload" onClick={load} title="Refresh shipments" aria-label="Refresh shipments"><Activity size={17} /></button></div>
        <div className="table-scroll"><table><thead><tr><th>TRACKING ID</th><th>CUSTOMER / RECIPIENT</th><th>ROUTE</th><th>METHOD</th><th>STATUS</th><th>CREATED</th><th /></tr></thead><tbody>
          {loading ? <tr><td colSpan="7"><LoadingPanel label="Loading shipments…" /></td></tr> : rows.length ? rows.map((parcel) => <tr key={parcel.id} className="clickable-row" onClick={() => openDetail(parcel)}><td><span className="tracking-code">{parcel.trackingId}</span></td><td><b>{parcel.customer?.displayName || 'Customer'}</b><small className="cell-sub">{parcel.recipientName}</small></td><td><span className="route-text">{parcel.origin} <span>→</span> {parcel.destination}</span></td><td><span className={`method-tag ${parcel.method?.toLowerCase()}`}>{parcel.method}</span></td><td><StatusPill status={parcel.status} /></td><td>{formatDate(parcel.createdAt)}</td><td><ChevronRight size={16} className="table-chevron" /></td></tr>) : <tr><td colSpan="7"><EmptyState icon={Box} title="No shipments found" text="Try changing the search or status filter." /></td></tr>}
        </tbody></table></div>
        <div className="table-foot"><span>Live operational records shared with the D2F app</span><PageControls total={total} offset={offset} limit={PAGE_SIZE} onPage={setOffset} /></div>
      </section>
      {selected && !editing && <ShipmentModal parcel={detail || selected} loading={!detail} busy={busy} token={token} notify={notify} currentUserId={currentUserId} canEditAllNotes={!staffAccess} onRefreshDetail={refreshDetail} onClose={() => { setSelected(null); setDetail(null); }} onUpdate={updateStatus} onEdit={staffAccess ? undefined : () => setEditing(true)} />}
      {editing && detail && <ShipmentFormModal token={token} notify={notify} parcel={detail} onClose={() => setEditing(false)} onCreated={(updated) => {
        setDetail(updated);
        setSelected(updated);
        setEditing(false);
        notify(`Shipment ${updated.trackingId} updated.`);
        load();
        refreshOverview();
      }} />}
      {createOpen && <ShipmentFormModal token={token} staffAccess={staffAccess} notify={notify} onClose={() => setCreateOpen(false)} onCreated={(parcel) => {
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

function ShipmentFormModal({ token, notify, onClose, onCreated, staffAccess = false, parcel = null }) {
  const [customers, setCustomers] = useState([]);
  const [customerTotal, setCustomerTotal] = useState(0);
  const [customerQuery, setCustomerQuery] = useState('');
  const [customerId, setCustomerId] = useState(parcel?.customerId || '');
  const [selectedCustomer, setSelectedCustomer] = useState(parcel?.customer || null);
  const [customerLoading, setCustomerLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [rescheduleReason, setRescheduleReason] = useState('');
  const [pickupWhenEdit, setPickupWhenEdit] = useState(parcel?.pickupScheduledAt ? localInputValue(new Date(parcel.pickupScheduledAt)) : '');
  const routeLocked = parcel?.container && parcel.container.status !== 'ARRIVED';
  const [form, setForm] = useState({
    recipientName: parcel?.recipientName || '',
    recipientPhone: parcel?.recipientPhone || '',
    recipientAddress: parcel?.recipientAddress || '',
    pickupAddress: parcel?.pickupAddress || '',
    deliveryMode: parcel?.deliveryMode || 'DROP_OFF',
    packageType: parcel?.packageType || 'BOX',
    weightKg: parcel?.weightKg ?? '',
    origin: parcel?.origin || 'Omaha, NE, USA',
    destination: parcel?.destination || 'Lomé, Togo',
    method: parcel?.method || 'AIR',
    notes: parcel?.notes || '',
  });

  useEffect(() => {
    let active = true;
    const timer = setTimeout(async () => {
      setCustomerLoading(true);
      try {
        const query = new URLSearchParams({ limit: String(PAGE_SIZE), offset: '0' });
        if (customerQuery.trim()) query.set('q', customerQuery.trim());
        const result = await request(`${staffAccess ? '/warehouse/directory' : '/admin'}/customers?${query}`, { token });
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
  }, [token, customerQuery, notify, staffAccess]);

  async function submit(event) {
    event.preventDefault();
    if (saving) return;
    if (!customerId) {
      setError('Choose a customer profile before saving the shipment.');
      return;
    }
    const routeProblem = routeError(form);
    if (routeProblem) {
      setError(routeProblem);
      return;
    }
    if (form.deliveryMode === 'PICKUP') {
      if (!form.pickupAddress.trim()) {
        setError('A pickup needs a collection address before it can be scheduled.');
        return;
      }
      if (pickupWhenEdit.trim() && (Number.isNaN(Date.parse(pickupWhenEdit)) || new Date(pickupWhenEdit).getTime() < Date.now())) {
        setError('Enter a future pickup date and time, or clear the window to set it later.');
        return;
      }
    }
    setSaving(true);
    setError('');
    try {
      const saved = await request(parcel ? `/parcels/${encodeURIComponent(parcel.id)}` : '/parcels', {
        token,
        method: parcel ? 'PATCH' : 'POST',
        body: JSON.stringify({
          customerId,
          ...form,
          weightKg: Number(form.weightKg),
          ...(parcel && form.deliveryMode === 'PICKUP' && pickupWhenEdit.trim() ? { pickupScheduledAt: new Date(pickupWhenEdit).toISOString(), rescheduleReason: rescheduleReason.trim() } : {}),
          ...(parcel ? { updatedAt: parcel.updatedAt } : {}),
        }),
      });
      onCreated(saved);
    } catch (error) {
      setError(error.message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop" onMouseDown={(event) => { if (!saving && event.target === event.currentTarget) onClose(); }}>
      <datalist id="d2f-route-locations">{ROUTE_LOCATIONS.map(l => <option key={l} value={l} />)}</datalist><section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="create-shipment-title">
        <div className="modal-header">
          <div><span className="eyebrow">{parcel ? parcel.trackingId : 'NEW OPERATIONAL RECORD'}</span><h2 id="create-shipment-title">{parcel ? 'Edit shipment' : 'Create a shipment'}</h2></div>
          <button className="icon-button" disabled={saving} onClick={onClose} aria-label="Close shipment form"><X size={19} /></button>
        </div>
        <form className="modal-body invite-form" onSubmit={submit}>
          {error && <div className="alert error-alert" role="alert">{error}</div>}
          <label>Find customer profile<input autoFocus value={customerQuery} onChange={(event) => { setCustomerQuery(event.target.value); if (!parcel) { setCustomerId(''); setSelectedCustomer(null); } }} placeholder="Search name, email, or phone…" /></label>
          <label>Customer<select required value={customerId} onChange={(event) => { setCustomerId(event.target.value); setSelectedCustomer(customers.find(customer => customer.id === event.target.value) || selectedCustomer); }} disabled={customerLoading || (!customers.length && !selectedCustomer)}>
            <option value="">{customerLoading ? 'Loading customer profiles…' : customers.length ? 'Select a customer' : 'No matching customer profiles'}</option>
            {selectedCustomer && !customers.some(customer => customer.id === selectedCustomer.id) && <option value={selectedCustomer.id}>{selectedCustomer.displayName}</option>}
            {customers.map((customer) => <option key={customer.id} value={customer.id}>{customer.displayName}{customer.email ? ` · ${customer.email}` : ''}{customer.userId ? ' · App account' : ' · Staff profile'}</option>)}
          </select></label>
          {customerTotal > customers.length && <p className="muted">Showing {formatNumber(customers.length)} of {formatNumber(customerTotal)} matching profiles. Search to find another customer.</p>}
          <p className="muted">A linked app account can see this shipment in its customer workspace. Staff-only profiles remain in operations records.</p>
          <label>Recipient name<input required pattern=".*\S.*" maxLength={120} value={form.recipientName} onChange={(event) => setForm({ ...form, recipientName: event.target.value })} /></label>
          <label>Delivery address<textarea maxLength={1000} value={form.recipientAddress} onChange={(event) => setForm({ ...form, recipientAddress: event.target.value })} /></label>
          {((form.method === 'ROAD' || form.deliveryMode === 'PICKUP')) && <label>Pickup address<textarea maxLength={1000} value={form.pickupAddress} onChange={(event) => setForm({ ...form, pickupAddress: event.target.value })} placeholder="Street address where D2F collects the parcel" /><small className="field-help">{form.deliveryMode === 'PICKUP' ? 'The customer asked D2F to collect the goods from this address.' : 'Same-city road deliveries need a pickup address that differs from the delivery address.'}</small></label>}
          {parcel && <div className="form-row"><label>Collection<select value={form.deliveryMode} onChange={(event) => setForm({ ...form, deliveryMode: event.target.value })}><option value="DROP_OFF">Warehouse drop-off</option><option value="PICKUP">D2F collects the goods (pickup)</option></select></label>{form.deliveryMode === 'PICKUP' && <label>Pickup date and time<input type="datetime-local" min={localInputValue()} value={pickupWhenEdit} onChange={(event) => setPickupWhenEdit(event.target.value)} /><small className="field-help">Leave empty to keep the currently scheduled slot.</small></label>}</div>}
          {parcel && form.deliveryMode === 'PICKUP' && <label>Pickup reschedule reason<input maxLength={300} value={rescheduleReason} onChange={(event) => setRescheduleReason(event.target.value)} placeholder="Why is the collection slot changing?" /></label>}
          <div className="form-row">
            <label>Recipient phone<input type="tel" maxLength={80} value={form.recipientPhone} onChange={(event) => setForm({ ...form, recipientPhone: event.target.value })} /></label>
            <label>Package type<select value={form.packageType} onChange={(event) => setForm({ ...form, packageType: event.target.value })}>{['BOX', 'SUITCASE', 'BARREL', 'TV', 'APPLIANCE', 'FURNITURE', 'PALLET', 'VEHICLE', 'DOCUMENTS', 'OTHER'].map((type) => <option key={type}>{type}</option>)}</select></label>
          </div>
          <div className="form-row">
            <label>Weight (kg)<input type="number" min="0.01" max="10000" step="0.01" required value={form.weightKg} onChange={(event) => setForm({ ...form, weightKg: event.target.value })} /></label>
            <label>Shipping method<select disabled={routeLocked} value={form.method} onChange={(event) => setForm({ ...form, method: event.target.value })}><option value="AIR">Air</option><option value="SEA">Sea</option><option value="ROAD">Road</option></select></label>
          </div>
          <div className="form-row">
            <label>Origin<input disabled={routeLocked} list="d2f-route-locations" required pattern=".*\S.*" maxLength={120} value={form.origin} onChange={(event) => setForm({ ...form, origin: event.target.value })} /></label>
            <label>Destination<input disabled={routeLocked} list="d2f-route-locations" required pattern=".*\S.*" maxLength={120} value={form.destination} onChange={(event) => setForm({ ...form, destination: event.target.value })} /></label>
          </div>
          <small className="field-help">Origin is where the shipment starts; the receiving D2F warehouse is recorded separately at intake. Domestic Togo cities are available for road routes. Air and sea need different cities; same-city road needs different pickup and delivery addresses.</small>
          <label>Staff note (optional)<input maxLength={1000} value={form.notes} onChange={(event) => setForm({ ...form, notes: event.target.value })} /></label>
          {routeLocked && <p className="muted">Route and method are managed by container {parcel.container.code}. Remove the parcel from a loading container to change them.</p>}
          {parcel?.container && parcel.container.status !== 'LOADING' && <p className="muted">The departure manifest keeps the details recorded at departure.</p>}
          <div className="alert info-alert"><ShieldCheck size={16} /> {parcel ? 'Corrections are saved to the shared shipment record and recorded in the admin audit trail.' : 'The shipment is saved to the shared D2F API and appears in staff operations.'}</div>
          <div className="form-row"><button type="button" className="button secondary" disabled={saving} onClick={onClose}>Cancel</button><button className="button primary full-button" disabled={saving || customerLoading || !customerId}>{saving ? <span className="spinner" /> : <PackageCheck size={16} />} {parcel ? 'Save changes' : 'Create shipment'}</button></div>
        </form>
      </section>
    </div>
  );
}

// Goods photos arrive from the API as raw bytes behind an Authorization
// header, so this component fetches each blob itself and turns it into an
// object URL for the <img> tag. Object URLs are revoked when it unmounts.
function GoodsPhotos({ parcelId, images, goods, token }) {
  const [urls, setUrls] = useState({});
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();
    const created = [];
    (async () => {
      for (const image of images || []) {
        try {
          const response = await fetch(
            `${getApiBaseUrl()}/parcels/${encodeURIComponent(parcelId)}/images/${encodeURIComponent(image.id)}/raw`,
            {
              headers: token ? { Authorization: `Bearer ${token}` } : {},
              signal: controller.signal,
            },
          );
          if (!response.ok) {
            if (response.status === 401) {
              window.dispatchEvent(new Event('d2f-session-expired'));
            }
            throw new Error(`A goods photo could not be loaded (${response.status}).`);
          }
          const url = URL.createObjectURL(await response.blob());
          created.push(url);
          setUrls((current) => ({ ...current, [image.id]: url }));
        } catch (loadError) {
          if (!controller.signal.aborted) setError(loadError.message);
        }
      }
    })();
    return () => {
      controller.abort();
      created.forEach((url) => URL.revokeObjectURL(url));
    };
  }, [parcelId, token]);

  return (
    <>
      {error && <div className="alert error-alert" role="alert">{error}</div>}
      <div className="photo-grid">
        {(images || []).map((image) => (
          <figure key={image.id} style={{ margin: 0 }}>
          <img
            className={urls[image.id] ? 'photo-thumb' : 'photo-thumb photo-loading'}
            src={urls[image.id]}
            alt={image.fileName || 'Goods photo'}
            title={image.fileName || ''}
          />
          <figcaption>{image.itemId ? goods.find((item) => item.id === image.itemId)?.name || 'Declared package' : 'Whole shipment'}</figcaption>
          </figure>
        ))}
      </div>
      <small className="field-help">Showing {images?.length || 0} of 8 optional goods photos attached to this shipment.</small>
    </>
  );
}

function staffStatusOptions(parcel) {
  if (parcel.serviceType === 'AIR_TRAVELLER' || parcel.status === 'OUT_FOR_DELIVERY') return [];
  return (TRANSITIONS[parcel.status] || []).filter(s => !['PICKUP_SCHEDULED','PICKED_UP','RECEIVED','OUT_FOR_DELIVERY','RELEASED'].includes(s) && (parcel.warehouseReceivedAt || !['PROCESSING','IN_TRANSIT'].includes(s)) && (!PICKUP_ONLY_STATUSES.has(s) || parcel.deliveryMode === 'PICKUP'));
}

function ShipmentModal({ parcel, loading, busy, onClose, onUpdate, onEdit, token, notify, currentUserId, canEditAllNotes, onRefreshDetail }) {
  const [next, setNext] = useState('');
  const [note, setNote] = useState('');
  const [locations, setLocations] = useState([]);
  const [locationId, setLocationId] = useState('');
  const [locationsError, setLocationsError] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [releasedToName, setReleasedToName] = useState('');
  const [releasedToId, setReleasedToId] = useState('');
  const [releasedAt, setReleasedAt] = useState(localInputValue());
  const [deliveredToName, setDeliveredToName] = useState(parcel.releasedToName || '');
  const [deliveredToId, setDeliveredToId] = useState(parcel.releasedToIdNumber || '');
  const [deliveredAt, setDeliveredAt] = useState(localInputValue());
  const [proofType, setProofType] = useState('');
  const [proofReference, setProofReference] = useState('');
  const [pickupWhen, setPickupWhen] = useState('');
  const [missedItems, setMissedItems] = useState({});
  const [formError, setFormError] = useState('');
  const [editingNote, setEditingNote] = useState(null);
  const [noteDraft, setNoteDraft] = useState('');
  const [noteBusy, setNoteBusy] = useState(false);
  const goods = Array.isArray(parcel.items) ? parcel.items : [];
  const goodsCount = goods.length;

  useEffect(() => {
    const options = staffStatusOptions(parcel);
    // Pickup requests default to scheduling the collection; everything else
    // defaults to the first available stage.
    const preferred =
      parcel.deliveryMode === 'PICKUP' && options.includes('PICKUP_SCHEDULED')
        ? 'PICKUP_SCHEDULED'
        : options[0];
    setNext(preferred || '');
    setConfirmed(false);
    setFormError('');
    setReleasedToName('');
    setReleasedToId('');
    setReleasedAt(localInputValue());
    setDeliveredToName(parcel.releasedToName || '');
    setDeliveredToId(parcel.releasedToIdNumber || '');
    setDeliveredAt(localInputValue());
    setProofType('');
    setProofReference('');
    setPickupWhen('');
    setMissedItems({});
    setEditingNote(null);
  }, [parcel.id, parcel.status, parcel.releasedToName, parcel.releasedToIdNumber]);

  useEffect(() => {
    let active = true;
    setLocationsError('');
    request('/warehouse/locations', { token })
      .then((list) => {
        if (!active) return;
        setLocations(list);
        if (list.length === 1) setLocationId(list[0].id);
      })
      .catch((error) => { if (active) setLocationsError(error.message); });
    return () => { active = false; };
  }, [token]);

  const containerManaged = parcel.container && parcel.container.status !== 'ARRIVED';
  // Mode-aware transition options: drop-off shipments skip the pickup stages
  // (REQUESTED → RECEIVED), pickup requests can be scheduled and collected.
  const available = containerManaged ? [] : staffStatusOptions(parcel);
  const needsFacility = FACILITY_REQUIRED_STATUSES.has(next);
  const needsConfirmation = CONFIRMATION_STATUSES.has(next);
  const isReleased = next === 'RELEASED';
  const isDelivered = next === 'DELIVERED';
  const isPickup = parcel.deliveryMode === 'PICKUP';
  const schedulingPickup = next === 'PICKUP_SCHEDULED';
  const collecting = next === 'PICKED_UP' && goods.length > 0;
  const missingGoods = goods.filter((item) => item.notCollectedReason && !item.collectedAt);

  function submit(event) {
    event.preventDefault();
    if (!next) return;
    if (needsFacility && !locationId) {
      setFormError('Select the D2F facility where this update is taking place.');
      return;
    }
    if (needsConfirmation && !confirmed) {
      setFormError('Confirm that you have physically verified this shipment at the selected facility.');
      return;
    }
    if (collecting && Object.values(missedItems).some((reason) => !reason.trim())) {
      setFormError('Record why each missing package was not collected.');
      return;
    }
    if (isReleased) {
      if (!releasedToName.trim()) { setFormError('Enter the name of the person receiving the parcel.'); return; }
      if (!releasedToId.trim()) { setFormError('Record the handover ID or reference before releasing the parcel.'); return; }
      if (!releasedAt || Number.isNaN(Date.parse(releasedAt))) { setFormError('Enter a valid handover date and time.'); return; }
    }
    if (isDelivered) {
      if (!deliveredToName.trim()) { setFormError('Enter the recipient name before confirming delivery.'); return; }
      if (!proofType) { setFormError('Select the proof of delivery recorded for this handover.'); return; }
      if (!proofReference.trim()) { setFormError('Record the proof reference (signature, photo, or ID details).'); return; }
      if (proofType === 'ID_CONFIRMATION' && !deliveredToId.trim()) { setFormError('Record the recipient ID number for an ID-confirmed delivery.'); return; }
      if (!deliveredAt || Number.isNaN(Date.parse(deliveredAt))) { setFormError('Enter a valid delivery date and time.'); return; }
    }
    if (schedulingPickup && pickupWhen.trim()) {
      if (Number.isNaN(Date.parse(pickupWhen)) || new Date(pickupWhen).getTime() < Date.now()) {
        setFormError('Enter a future pickup date and time, or leave the window empty to keep the customer\u2019s requested slot.');
        return;
      }
    }
    setFormError('');
    const payload = {
      status: next,
      note: note.trim(),
      ...(collecting ? { missedItems: Object.entries(missedItems).map(([itemId, reason]) => ({ itemId, reason: reason.trim() })) } : {}),
      ...(locationId ? { locationId } : {}),
      ...(confirmed ? { confirmed: true } : {}),
      ...(schedulingPickup && pickupWhen.trim() ? { pickupScheduledAt: new Date(pickupWhen).toISOString() } : {}),
      ...(isReleased ? {
        releasedToName: releasedToName.trim(),
        releasedToIdNumber: releasedToId.trim(),
        releasedAt: new Date(releasedAt).toISOString(),
      } : {}),
      ...(isDelivered ? {
        deliveredToName: deliveredToName.trim(),
        deliveredToIdNumber: deliveredToId.trim(),
        deliveredAt: new Date(deliveredAt).toISOString(),
        deliveryProofType: proofType,
        deliveryProofReference: proofReference.trim(),
      } : {}),
    };
    onUpdate(payload);
  }

  function canEditNote(event) {
    return Boolean(currentUserId) && (canEditAllNotes || event.actorId === currentUserId);
  }

  async function saveNote(event) {
    setNoteBusy(true);
    try {
      await request(`/parcels/${encodeURIComponent(parcel.id)}/events/${encodeURIComponent(event.id)}/note`, {
        token,
        method: 'PATCH',
        body: JSON.stringify({ note: noteDraft.trim() }),
      });
      setEditingNote(null);
      notify('Operational note corrected.');
      await onRefreshDetail();
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setNoteBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <datalist id="d2f-route-locations">{ROUTE_LOCATIONS.map(l => <option key={l} value={l} />)}</datalist><section className="modal shipment-modal" role="dialog" aria-modal="true" aria-labelledby="shipment-title">
        <div className="modal-header"><div><span className="eyebrow">SHIPMENT RECORD</span><h2 id="shipment-title">{parcel.trackingId}</h2></div><button className="icon-button" onClick={onClose} aria-label="Close shipment details"><X size={19} /></button></div>
        {loading ? <LoadingPanel label="Loading tracking history…" /> : <div className="modal-body">
          <div className="detail-status"><span><small>CURRENT STATUS</small><StatusPill status={parcel.status} /></span><span><small>CREATED</small><b>{formatDate(parcel.createdAt, { year: 'numeric', month: 'long', day: 'numeric' })}</b></span></div>
          <div className="detail-grid"><div><small>Customer</small><b>{parcel.customer?.displayName || '—'}</b></div><div><small>Recipient</small><b>{parcel.recipientName}</b></div><div><small>Route</small><b>{parcel.origin} → {parcel.destination}</b></div><div><small>Package</small><b>{parcel.packageType} · {parcel.weightKg} kg</b></div></div>
          <div className="detail-grid"><div><small>Recipient phone</small><b>{parcel.recipientPhone || '—'}</b></div><div><small>Delivery address</small><b>{parcel.recipientAddress || '—'}</b></div><div><small>Pickup address</small><b>{parcel.pickupAddress || '—'}</b></div><div><small>Shipping method</small><b>{parcel.method}</b></div></div>
          <div className="detail-grid">
            <div><small>Customer contact</small><b>{[parcel.customer?.phone, parcel.customer?.email].filter(Boolean).join(' · ') || '—'}</b></div>
            <div><small>Collection</small><b>{parcel.deliveryMode === 'PICKUP' ? 'D2F collects the goods' : 'Warehouse drop-off'}</b></div>
            <div><small>D2F confirmed pickup</small><b>{parcel.pickupScheduledAt ? formatDate(parcel.pickupScheduledAt, { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'To be confirmed'}</b></div>
            <div><small>Goods pieces</small><b>{goodsCount ? `${goodsCount} package${goodsCount === 1 ? '' : 's'}` : '—'}</b></div>
          </div>
          <div className="detail-grid"><div><small>Service</small><b>{parcel.serviceType === 'AIR_CARGO' ? 'D2F Air Cargo' : parcel.serviceType === 'AIR_TRAVELLER' ? 'D2F Connect · Air Traveller' : parcel.method}</b></div><div><small>Customer contents declaration</small><b>{parcel.restrictionsAcknowledgedAt ? formatDate(parcel.restrictionsAcknowledgedAt, { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Not recorded on this legacy / staff registration'}</b></div></div>
          {missingGoods.length > 0 && <div className="alert error-alert" role="status">Collected {goods.length - missingGoods.length} of {goods.length} packages. Missing packages remain recorded below.</div>}
          <CustodyActions parcel={parcel} token={token} onSaved={onRefreshDetail} isAdmin={canEditAllNotes} />
          <AirCargoReference parcel={parcel} token={token} notify={notify} onSaved={onRefreshDetail} />
      {goods.length > 0 && <div className="goods-list">{goods.map((item, index) => <div className="goods-row" key={item.id || index}>
            <b>{`${item.type || 'BOX'} ${index + 1} of ${goods.length}`} · {item.name}</b>
            <span>{item.quantity} contents unit{item.quantity === 1 ? '' : 's'}{item.weightKg != null ? ` · ${item.weightKg} kg` : ''}{item.details ? ` · ${item.details}` : ''}</span>
            {item.lengthCm != null && item.widthCm != null && item.heightCm != null && <span>{`${item.lengthCm} × ${item.widthCm} × ${item.heightCm} cm`}</span>}
            {item.packageCode && <span>Package code: {item.packageCode}</span>}
            {item.notCollectedReason && !item.collectedAt && <strong>Not collected: {item.notCollectedReason}</strong>}
          </div>)}</div>}
          <div className="detail-grid"><div><small>Staff note</small><b>{parcel.notes || '—'}</b></div><div><small>Released to</small><b>{parcel.releasedToName ? `${parcel.releasedToName}${parcel.releasedAt ? ` · ${formatDate(parcel.releasedAt, { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}` : ''}` : '—'}</b></div><div><small>Delivered to</small><b>{parcel.deliveredToName || '—'}</b></div><div><small>Proof of delivery</small><b>{parcel.deliveryProofType ? `${DELIVERY_PROOF_TYPES[parcel.deliveryProofType] || parcel.deliveryProofType}${parcel.deliveryProofReference ? ` · ${parcel.deliveryProofReference}` : ''}` : '—'}</b></div></div>
          {parcel.images?.length > 0 && <div className="goods-photos"><h3 className="modal-section-title">{`Goods photos (${parcel.images.length})`}</h3><GoodsPhotos parcelId={parcel.id} images={parcel.images} goods={goods} token={token} /></div>}
          {onEdit && <button className="button secondary" disabled={busy} onClick={onEdit}><Pencil size={16} /> Edit shipment</button>}
          <h3 className="modal-section-title">Tracking history</h3>
          <div className="timeline">{parcel.events?.map((event) => <div className="timeline-item" key={event.id}><span className="timeline-dot" style={{ '--status-color': STATUS_COLORS[event.status] || '#788295' }} /><div><b>{statusLabel(event.status)}</b><span>{event.note || event.location || 'Status updated'}</span><small>{formatDate(event.createdAt, { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}{event.actor?.fullName ? ` · ${event.actor.fullName}` : ''}{event.location ? ` · ${event.location}` : ''}</small>{canEditNote(event) && <button type="button" className="text-button timeline-note-edit" onClick={() => { setEditingNote(event); setNoteDraft(event.note || ''); }}>Correct note</button>}{editingNote?.id === event.id && <form className="note-editor" onSubmit={(submitEvent) => { submitEvent.preventDefault(); saveNote(event); }}><label>Operational note<textarea autoFocus maxLength={1000} rows={3} value={noteDraft} onChange={(changeEvent) => setNoteDraft(changeEvent.target.value)} /></label><div className="heading-actions"><button type="button" className="button secondary" disabled={noteBusy} onClick={() => setEditingNote(null)}>Cancel</button><button className="button primary" disabled={noteBusy}>{noteBusy ? <span className="spinner" /> : <Check size={15} />} Save correction</button></div></form>}</div></div>)}</div>
          {available.length > 0 ? <form className="status-update-form" onSubmit={submit}>
            <h3 className="modal-section-title">Update shipment</h3>
            <div className="form-row">
              <label>Move to<select value={next} onChange={(event) => { setNext(event.target.value); setConfirmed(false); setFormError(''); }}>{available.map((state) => <option key={state} value={state}>{statusLabel(state)}</option>)}</select></label>
              <label>Facility<select value={locationId} onChange={(event) => setLocationId(event.target.value)} disabled={!needsFacility || Boolean(locationsError)}><option value="">{locationsError ? 'Facilities unavailable' : 'Select D2F facility'}</option>{locations.map((location) => <option key={location.id} value={location.id}>{location.name} · {location.city}, {location.country}</option>)}</select></label>
            </div>
            {needsFacility && !locationsError && <small className="field-help">The facility must match where the parcel physically is. Staff can only confirm at their assigned facility; administrators can operate anywhere.</small>}
            {locationsError && <div className="alert error-alert" role="alert">{locationsError}</div>}
            {needsConfirmation && <label className="confirm-check"><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I physically verified this shipment at the selected facility.</label>}
            {schedulingPickup && <div className="handover-fields"><label>Pickup date and time<input type="datetime-local" min={localInputValue()} value={pickupWhen} onChange={(event) => setPickupWhen(event.target.value)} /></label><small className="field-help">Optional — confirm or adjust the customer&#39;s requested slot. Leave empty to keep {parcel.pickupScheduledAt ? 'the currently scheduled window' : "the customer's requested slot"}.</small></div>}
            {collecting && <fieldset className="handover-fields"><legend>Collection checklist</legend>
              <small className="field-help">Mark only the packages that were not collected. Record a reason for each missing package.</small>
              {goods.map((item, index) => <div key={item.id}>
                <label className="confirm-check"><input type="checkbox" checked={Object.hasOwn(missedItems, item.id)} onChange={(event) => setMissedItems((current) => {
                  const changed = { ...current };
                  if (event.target.checked) changed[item.id] = ''; else delete changed[item.id];
                  return changed;
                })} />{`Not collected: ${item.name} (${index + 1} of ${goods.length})`}</label>
                {Object.hasOwn(missedItems, item.id) && <label>Reason for {item.name}<input maxLength={300} value={missedItems[item.id]} onChange={(event) => setMissedItems({ ...missedItems, [item.id]: event.target.value })} /></label>}
              </div>)}
            </fieldset>}
            {isReleased && <div className="handover-fields"><div className="form-row"><label>Received by<input required maxLength={120} value={releasedToName} onChange={(event) => setReleasedToName(event.target.value)} placeholder="Person collecting the parcel" /></label><label>Handover ID / reference<input required maxLength={80} value={releasedToId} onChange={(event) => setReleasedToId(event.target.value)} placeholder="ID number or collection code" /></label></div><label>Handover date and time<input type="datetime-local" required value={releasedAt} max={localInputValue()} onChange={(event) => setReleasedAt(event.target.value)} /></label></div>}
            {isDelivered && <div className="handover-fields"><div className="form-row"><label>Delivered to<input required maxLength={120} value={deliveredToName} onChange={(event) => setDeliveredToName(event.target.value)} /></label><label>Recipient ID / reference<input maxLength={80} value={deliveredToId} onChange={(event) => setDeliveredToId(event.target.value)} placeholder={proofType === 'ID_CONFIRMATION' ? 'Required for ID confirmation' : 'Optional reference'} /></label></div><div className="form-row"><label>Proof of delivery<select required value={proofType} onChange={(event) => setProofType(event.target.value)}><option value="">Select proof</option>{Object.entries(DELIVERY_PROOF_TYPES).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label>Proof reference<input required maxLength={300} value={proofReference} onChange={(event) => setProofReference(event.target.value)} placeholder="Signature, photo, or ID reference" /></label></div><label>Delivery date and time<input type="datetime-local" required value={deliveredAt} max={localInputValue()} onChange={(event) => setDeliveredAt(event.target.value)} /></label></div>}
            <label>Operational note<textarea maxLength={1000} rows={3} value={note} onChange={(event) => setNote(event.target.value)} placeholder="Add an operational note (optional)" /></label>
            {formError && <div className="alert error-alert" role="alert">{formError}</div>}
            <button className="button primary" disabled={busy || !next}>{busy ? <span className="spinner" /> : <Check size={16} />} Save status update</button>
          </form> : <div className="complete-note"><Check size={16} /> {containerManaged ? `Managed by container ${parcel.container.code}. Record freight departure and arrival in Containers.` : (parcel.status === 'DELIVERED' ? "Delivery is complete." : parcel.status === 'OUT_FOR_DELIVERY' ? "The assigned driver confirms actual delivery in Driver tasks." : "Use the pickup and warehouse custody actions above for the next physical step.")}</div>}
        </div>}
      </section>
    </div>
  );
}

function Customers({ token, notify, refreshKey, staffAccess = false }) {
  const [customers, setCustomers] = useState([]);
  const [search, setSearch] = useState('');
  const [offset, setOffset] = useState(0);
  const [total, setTotal] = useState(0);
  const [reloadCount, setReloadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [addOpen, setAddOpen] = useState(false);
  const [editingCustomer, setEditingCustomer] = useState(null);
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
        const result = await request(`${staffAccess ? '/warehouse/directory' : '/admin'}/customers?${params}`, { token });
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
  }, [token, search, offset, notify, refreshKey, reloadCount, staffAccess]);
  async function addCustomer(event) {
    event.preventDefault();
    setSaving(true);
    try {
      const created = await request(editingCustomer ? `/customers/${editingCustomer.id}` : '/customers', {
        token,
        method: editingCustomer ? 'PATCH' : 'POST',
        body: JSON.stringify(Object.fromEntries(Object.entries(form).map(([key, value]) => [key, value.trim()]))),
      });
      setAddOpen(false);
      setForm({ displayName: '', email: '', phone: '', address: '', city: '', country: '' });
      notify(editingCustomer ? 'Customer profile updated.' : 'Customer profile added.');
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
        <button className="button primary" onClick={() => { setEditingCustomer(null); setForm({ displayName: '', email: '', phone: '', address: '', city: '', country: '' }); setAddOpen(true); }}><UserRound size={16} /> Add customer</button>
      </PageHeading>
      <section className="panel table-panel">
        <div className="table-toolbar"><SearchInput value={search} onChange={(value) => { setSearch(value); setOffset(0); }} placeholder="Search name, email, or phone…" /><span className="toolbar-count">{formatNumber(total)} customers</span></div>
        <div className="table-scroll"><table><thead><tr><th>CUSTOMER</th><th>CONTACT</th><th>ADDRESS</th><th>ADDED</th></tr></thead><tbody>
          {loading ? <tr><td colSpan="4"><LoadingPanel label="Loading customers…" /></td></tr> : customers.length ? customers.map((customer) => <tr key={customer.id}><td><span className="customer-cell"><span className="avatar customer-avatar">{initials(customer.displayName)}</span><span className="user-cell-info"><button disabled={staffAccess} className="text-button" onClick={() => { setEditingCustomer(customer); setForm(Object.fromEntries(['displayName', 'email', 'phone', 'address', 'city', 'country'].map(key => [key, customer[key] || '']))); setAddOpen(true); }}>{customer.displayName}</button><small>{customer.userId ? 'Customer app account linked' : 'Staff profile only'}</small></span></span></td><td><b>{customer.email || '—'}</b><small className="cell-sub">{customer.phone || 'No phone provided'}</small></td><td><span className="address-cell">{[customer.address, customer.city, customer.country].filter(Boolean).join(', ') || '—'}</span></td><td>{formatDate(customer.createdAt)}</td></tr>) : <tr><td colSpan="4"><EmptyState icon={UserRound} title="No customers found" text="Customers appear here when added to the shipping records." /></td></tr>}
        </tbody></table></div>
        <div className="table-foot"><span>Customer profiles shared with D2F shipping operations</span><PageControls total={total} offset={offset} limit={PAGE_SIZE} onPage={setOffset} /></div>
      </section>
      {addOpen && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setAddOpen(false); }}><section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="customer-title"><div className="modal-header"><div><span className="eyebrow">CUSTOMER RECORD</span><h2 id="customer-title">{editingCustomer ? "Edit customer" : "Add a customer"}</h2></div><button className="icon-button" onClick={() => setAddOpen(false)} aria-label="Close customer form"><X size={19} /></button></div><form className="modal-body invite-form" onSubmit={addCustomer}><label>Full name<input autoFocus required maxLength={120} value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} placeholder="Customer name" /></label><div className="form-row"><label>Email address<input type="email" value={form.email} onChange={(event) => setForm({ ...form, email: event.target.value })} placeholder="name@example.com" /></label><label>Phone<input value={form.phone} onChange={(event) => setForm({ ...form, phone: event.target.value })} placeholder="+1 402 555 0100" /></label></div><label>Street address<input value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} placeholder="Address (optional)" /></label><div className="form-row"><label>City<input value={form.city} onChange={(event) => setForm({ ...form, city: event.target.value })} placeholder="City" /></label><label>Country<select value={form.country} onChange={(event) => setForm({ ...form, country: event.target.value })}><option value="">Choose country (optional)</option>{SERVICE_COUNTRIES.map(c => <option key={c}>{c}</option>)}</select></label></div><div className="alert info-alert"><ShieldCheck size={16} /> This creates a shipping profile; it does not create an app login account.</div><button className="button primary full-button" disabled={saving}>{saving ? <span className="spinner" /> : <Check size={16} />} Save customer profile</button></form></section></div>}
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
      <PageHeading eyebrow="PEOPLE & PERMISSIONS" title="Team & access" subtitle="Review account roles and invite trusted staff, drivers, or administrators." >
        <button className="button primary" onClick={() => { setInvite(null); setInviteOpen(true); }}><UsersRound size={16} /> Create invitation</button>
      </PageHeading>
      <section className="panel table-panel">
        <div className="table-toolbar"><SearchInput value={search} onChange={(value) => { setSearch(value); setOffset(0); }} placeholder="Search by name or email…" /><label className="select-wrap filter-select"><select value={role} onChange={(event) => { setRole(event.target.value); setOffset(0); }}><option value="ALL">All roles</option><option value="ADMIN">Admin</option><option value="STAFF">Staff</option><option value="DRIVER">Driver</option><option value="CUSTOMER">Customer</option></select><ChevronDown size={15} /></label></div>
        <div className="table-scroll"><table><thead><tr><th>ACCOUNT</th><th>ROLE</th><th>LOCATION</th><th>JOINED</th><th>ACCESS</th><th /></tr></thead><tbody>
          {loading ? <tr><td colSpan="6"><LoadingPanel label="Loading accounts…" /></td></tr> : users.length ? users.map((user) => <tr key={user.id}><td><span className="customer-cell"><span className="avatar customer-avatar">{initials(user.fullName)}</span><span className="user-cell-info"><b>{user.fullName}</b><small>{user.email}</small></span></span></td><td><span className={`role-tag ${user.role.toLowerCase()}`}>{user.role}</span></td><td><UserLocation token={token} user={user} notify={notify} onSaved={load} /></td><td>{formatDate(user.createdAt)}</td><td><span className={`access-indicator ${user.isActive ? 'enabled' : 'disabled'}`}><i />{user.isActive ? 'Active' : 'Disabled'}</span></td><td>{user.id !== currentUserId && <button className={`text-button account-action ${user.isActive ? 'danger-text' : ''}`} disabled={pending === user.id} onClick={() => toggleActive(user)}>{pending === user.id ? 'Saving…' : user.isActive ? 'Disable' : 'Reactivate'}</button>}</td></tr>) : <tr><td colSpan="6"><EmptyState icon={UsersRound} title="No matching accounts" text="Try a different role or search term." /></td></tr>}
        </tbody></table></div>
        <div className="table-foot"><span>Roles and access are enforced by the backend</span><PageControls total={total} offset={offset} limit={PAGE_SIZE} onPage={setOffset} /></div>
      </section>
      {inviteOpen && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setInviteOpen(false); }}><section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="invite-title"><div className="modal-header"><div><span className="eyebrow">SECURE TEAM ONBOARDING</span><h2 id="invite-title">{invite ? 'Invitation ready' : 'Invite a teammate'}</h2></div><button className="icon-button" onClick={() => setInviteOpen(false)} aria-label="Close invitation"><X size={19} /></button></div>{invite ? <div className="modal-body"><div className="invite-success"><span><Check size={20} /></span><div><b>{invite.role} invitation created</b><small>For {invite.email} · expires in {invite.expiresInDays} days</small></div></div><label className="invite-code-label">ONE-TIME SIGNUP CODE</label><div className="invite-code"><code>{invite.invitation}</code><button className="button secondary" onClick={copyInvite}><Copy size={15} /> Copy</button></div><div className="alert warning-alert">This code grants {invite.role.toLowerCase()} access. Send it only to {invite.email} through a private channel. The invitee must sign up with that exact email.</div><button className="button primary full-button" onClick={() => setInviteOpen(false)}>Done</button></div> : <form className="modal-body invite-form" onSubmit={createInvite}><p className="muted">Invitations are issued by an authenticated administrator and are bound to the recipient’s exact email address.</p><label>Email address<input autoFocus type="email" required value={inviteEmail} onChange={(event) => setInviteEmail(event.target.value)} placeholder="teammate@example.com" /></label><label>Role<select value={inviteRole} onChange={(event) => setInviteRole(event.target.value)}><option value="STAFF">Staff · shipping operations</option><option value="DRIVER">Driver · delivery workflow</option><option value="ADMIN">Admin · full workspace access</option></select></label><div className="alert info-alert"><ShieldCheck size={16} /> Administrator invitations can only be created by a signed-in administrator and remain bound to one email and one role.</div><button className="button primary full-button" disabled={inviteBusy}>{inviteBusy ? <span className="spinner" /> : <UsersRound size={16} />} Generate secure invitation</button></form>}</section></div>}
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

function ChangePasswordModal({ token, onClose, notify, onChanged }) {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit(event) {
    event.preventDefault();
    setError('');
    if (newPassword.length < 8) { setError('Use at least 8 characters for the new password.'); return; }
    if (newPassword !== confirmPassword) { setError('The new passwords do not match.'); return; }
    setBusy(true);
    try {
      const result = await request('/auth/password/change', {
        token,
        method: 'POST',
        body: JSON.stringify({ currentPassword, newPassword }),
      });
      saveSession(result.token, result.user);
      onChanged(result);
      notify('Password updated. Other devices have been signed out.');
      onClose();
    } catch (problem) {
      setError(problem.message || 'Unable to change the password.');
    } finally {
      setBusy(false);
    }
  }

  return <div className="modal-backdrop" onMouseDown={(event) => { if (!busy && event.target === event.currentTarget) onClose(); }}><section className="modal invite-modal" role="dialog" aria-modal="true" aria-labelledby="password-title"><div className="modal-header"><div><span className="eyebrow">ACCOUNT SECURITY</span><h2 id="password-title">Change password</h2></div><button className="icon-button" disabled={busy} onClick={onClose} aria-label="Close password form"><X size={19} /></button></div><form className="modal-body invite-form" onSubmit={submit}><p className="muted">Changing your password signs out every other active device and keeps this dashboard signed in.</p><label>Current password<input autoFocus type="password" autoComplete="current-password" required value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} /></label><label>New password<input type="password" autoComplete="new-password" minLength={8} required value={newPassword} onChange={(event) => setNewPassword(event.target.value)} /><small className="field-help">At least 8 characters and no more than 72 bytes.</small></label><label>Confirm new password<input type="password" autoComplete="new-password" minLength={8} required value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} /></label>{error && <div className="alert error-alert" role="alert">{error}</div>}<div className="form-row"><button type="button" className="button secondary" disabled={busy} onClick={onClose}>Cancel</button><button className="button primary full-button" disabled={busy}>{busy ? <span className="spinner" /> : <KeyRound size={16} />} Update password</button></div></form></section></div>;
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
  const [page, setPage] = useState(() => getSavedSession()?.user?.role === 'STAFF' ? 'shipments' : 'overview');
  const [days, setDays] = useState(30);
  const [overview, setOverview] = useState(null);
  const [overviewLoading, setOverviewLoading] = useState(false);
  const [toast, setToast] = useState(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const notify = useCallback((message, type = 'success') => setToast({ message, type, key: Date.now() }), []);
  const token = session?.token;
  const isAdmin = session?.user?.role === 'ADMIN';

  const loadOverview = useCallback(async () => {
    if (!token || !isAdmin) return;
    setOverviewLoading(true);
    try {
      setOverview(await request(`/admin/overview?days=${days}`, { token }));
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setOverviewLoading(false);
    }
  }, [token, days, notify, isAdmin]);

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
      if (!['ADMIN', 'STAFF'].includes(result.user?.role)) throw new Error('This account no longer has Admin access.');
      setSession({ ...saved, user: result.user });
      if (result.user.role === 'STAFF') setPage('shipments');
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
        <Header page={page} onMenu={() => setMenuOpen(true)} user={session.user} onRefresh={page === 'overview' ? loadOverview : () => setRefreshKey((value) => value + 1)} refreshing={refreshing} onChangePassword={() => setPasswordOpen(true)} />
        <main className="content">
          {isAdmin && page === 'overview' && <Overview data={overview} days={days} onPeriod={setDays} loading={overviewLoading} onGo={setPage} />}
          {page === 'shipments' && <Shipments staffAccess={!isAdmin} token={token} notify={notify} refreshOverview={loadOverview} refreshKey={refreshKey} currentUserId={session.user.id} key="shipments" />}
          {page === 'connect' && <ConnectOperations token={token} notify={notify} refreshKey={refreshKey} isAdmin={isAdmin} />}
          {page === 'containers' && <Containers token={token} notify={notify} refreshKey={refreshKey} />}
          {isAdmin && page === 'locations' && <Locations token={token} notify={notify} refreshKey={refreshKey} />}
          {page === 'bookings' && <Shipments staffAccess={!isAdmin} token={token} notify={notify} refreshOverview={loadOverview} refreshKey={refreshKey} currentUserId={session.user.id} bookings key="bookings" />}
          {isAdmin && page === 'marketplace' && <Commerce kind="MARKETPLACE" token={token} notify={notify} refreshKey={refreshKey} key="marketplace" />}
          {isAdmin && page === 'buy-for-me' && <Commerce kind="BUY_FOR_ME" token={token} notify={notify} refreshKey={refreshKey} key="buy-for-me" />}
          {page === 'customers' && <Customers staffAccess={!isAdmin} token={token} notify={notify} refreshKey={refreshKey} key="customers" />}
          {isAdmin && page === 'team' && <Team token={token} notify={notify} refreshKey={refreshKey} currentUserId={session.user.id} key="team" />}
          {isAdmin && page === 'system' && <SystemHealth token={token} notify={notify} refreshKey={refreshKey} key="system" />}
          <footer className="page-footer"><span>© {new Date().getFullYear()} D2F Global</span><span><ShieldCheck size={13} /> {isAdmin ? 'Admin' : 'Staff'} operations · Data from D2F API</span></footer>
        </main>
      </div>
      {passwordOpen && <ChangePasswordModal token={token} notify={notify} onClose={() => setPasswordOpen(false)} onChanged={(result) => setSession((existing) => ({ ...existing, token: result.token, user: result.user }))} />}
      <Toast toast={toast} onClose={() => setToast(null)} />
    </div>
  ) : (
    <>
      <Login onSignedIn={(value) => { setSession(value); setPage(value.user.role === 'STAFF' ? 'shipments' : 'overview'); setToast({ message: 'Welcome to your Admin dashboard.', type: 'success', key: Date.now() }); }} />
      <Toast toast={toast} onClose={() => setToast(null)} />
    </>
  );
}
