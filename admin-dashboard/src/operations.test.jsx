import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, expect, it, vi } from 'vitest';
import { Containers, Locations } from './warehouse.jsx';
import { Commerce, money } from './commerce.jsx';
import { SERVICE_COUNTRIES } from './service-area.js';
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const origin = { id: 'oma', code: 'OMA', city: 'Omaha, NE', country: 'United States', name: 'Omaha Warehouse' };
const destination = { id: 'lom', code: 'LOM', city: 'Lomé', country: 'Togo', name: 'Lomé Facility' };
const parcel = { id: 'p1', trackingId: 'D2F000000000001', recipientName: 'Kossi Mensah', customer: { displayName: 'Ama Boateng' }, weightKg: 12.5 };
const baseContainer = { id: 'c1', code: 'QA-SEA-001', method: 'SEA', status: 'LOADING', origin, destination, _count: { parcels: 0 }, parcels: [], events: [] };
beforeEach(() => { vi.restoreAllMocks(); localStorage.clear(); sessionStorage.clear(); });
it('container scan errors preserve input; loading and departure require the real API and confirmation', async () => {
  let c = structuredClone(baseContainer), failScan = true;
  const writes = [];
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => {
    const path = new URL(url).pathname;
    if (options.method === 'POST') {
      const body = JSON.parse(options.body); writes.push({ path, body });
      if (path.endsWith('/parcels')) {
        if (failScan) return json({ error: 'Parcel and container shipping methods must match.' }, 409);
        c = { ...c, parcels: [parcel], _count: { parcels: 1 } }; return json({ alreadyLoaded: false }, 201);
      }
      if (path.endsWith('/events')) { c = { ...c, status: body.action }; return json(c, 201); }
    }
    if (path.endsWith('/containers/c1')) return json(c);
    if (path.endsWith('/containers')) return json({ containers: [c], total: 1 });
    throw new Error(`Unexpected path ${path}`);
  }));
  const user = userEvent.setup(), notify = vi.fn();
  render(<Containers token="local-test-token" notify={notify} refreshKey={0} />);
  await user.click(await screen.findByRole('button', { name: 'QA-SEA-001' }));
  const dialog = await screen.findByRole('dialog', { name: 'QA-SEA-001' });
  await user.type(await within(dialog).findByLabelText('Tracking number to load'), parcel.trackingId);
  await user.click(within(dialog).getByRole('button', { name: 'Load parcel', exact: true }));
  expect(await within(dialog).findByRole('alert')).toHaveTextContent('shipping methods must match');
  expect(within(dialog).getByLabelText('Tracking number to load')).toHaveValue(parcel.trackingId);
  failScan = false;
  await user.click(within(dialog).getByRole('button', { name: 'Load parcel', exact: true }));
  expect(await within(dialog).findByText(parcel.trackingId)).toBeInTheDocument();
  await user.click(within(dialog).getByRole('button', { name: 'Confirm departure', exact: true }));
  expect(writes.filter(w => w.path.endsWith('/events'))).toHaveLength(0);
  await user.click(within(dialog).getByRole('button', { name: 'Cancel', exact: true }));
  await user.click(within(dialog).getByRole('button', { name: 'Confirm departure', exact: true }));
  await user.click(within(dialog).getByRole('button', { name: 'Confirm', exact: true }));
  await waitFor(() => expect(writes.at(-1).body).toEqual({ action: 'DEPARTED' }));
  expect(await within(dialog).findByRole('button', { name: 'Record arrival' })).toBeInTheDocument();
  expect(within(dialog).queryByLabelText('Tracking number to load')).toBeNull();
});
it('location country choices stay inside the agreed service area and errors keep form values', async () => {
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => options.method === 'POST' ? json({ error: 'This location code already exists.' }, 409) : json([origin, destination])));
  const user = userEvent.setup();
  render(<Locations token="test" notify={vi.fn()} refreshKey={0} />);
  await user.click(screen.getByRole('button', { name: 'Add location' }));
  const dialog = screen.getByRole('dialog', { name: 'Add a location' });
  expect(within(dialog).getAllByRole('option').map(o => o.textContent)).toEqual(SERVICE_COUNTRIES);
  await user.type(within(dialog).getByLabelText('Facility name'), 'Brussels Facility');
  await user.type(within(dialog).getByLabelText('Location code'), 'BRU-1');
  await user.type(within(dialog).getByLabelText('City', { exact: true }), 'Brussels');
  await user.selectOptions(within(dialog).getByLabelText(/Country/), 'Belgium');
  await user.click(within(dialog).getByRole('button', { name: 'Save location' }));
  expect(await within(dialog).findByRole('alert')).toHaveTextContent('already exists');
  expect(within(dialog).getByLabelText('Facility name')).toHaveValue('Brussels Facility');
});
it('Marketplace records a priced product and availability without losing the existing catalog', async () => {
  const products = [], writes = [];
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => {
    if (options.method === 'POST') { const body = JSON.parse(options.body); writes.push(body); products.push({ id: 'prod1', ...body }); return json(products[0], 201); }
    return json({ products, orders: [], total: 0, transitions: {} });
  }));
  const user = userEvent.setup();
  render(<Commerce kind="MARKETPLACE" token="test" notify={vi.fn()} refreshKey={0} />);
  await screen.findByText('Build your catalog');
  await user.click(screen.getByRole('button', { name: 'Add product' }));
  const dialog = screen.getByRole('dialog', { name: 'Add a product' });
  await user.type(within(dialog).getByLabelText('Product title'), 'Household pack');
  await user.type(within(dialog).getByLabelText('Category'), 'Household');
  await user.type(within(dialog).getByLabelText('Unit price'), '25.50');
  await user.click(within(dialog).getByLabelText('Available for admin-recorded orders'));
  await user.click(within(dialog).getByRole('button', { name: 'Save product' }));
  expect(await screen.findByText('Household pack')).toBeInTheDocument();
  expect(writes[0]).toMatchObject({ priceMinor: 2550, currency: 'USD', isActive: true });
  expect(money(1000, 'XOF')).toContain('1,000');
});
it('Buy For Me saves a manual quote and preserves it after an API error', async () => {
  let order = { id: 'o1', kind: 'BUY_FOR_ME', title: 'Laptop request', customer: { displayName: 'Ama Boateng' }, quantity: 1, currency: 'EUR', status: 'REQUESTED', amountMinor: null, createdAt: '2026-10-24T09:00:00Z' }, failed = true;
  const writes = [];
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => {
    if (options.method === 'PATCH') { const body = JSON.parse(options.body); writes.push(body); if (failed) return json({ error: 'Connection unavailable. Retry your quote.' }, 503); order = { ...order, ...body }; return json(order); }
    return json({ products: [], orders: [order], total: 1, transitions: { REQUESTED: ['QUOTED', 'CANCELLED'], QUOTED: ['ACCEPTED', 'CANCELLED'] } });
  }));
  const user = userEvent.setup();
  render(<Commerce kind="BUY_FOR_ME" token="test" notify={vi.fn()} refreshKey={0} />);
  await user.click(await screen.findByRole('button', { name: 'Laptop request', exact: true }));
  const dialog = screen.getByRole('dialog', { name: 'Laptop request' });
  await user.type(within(dialog).getByLabelText('Total quote (EUR)'), '150.00');
  await user.selectOptions(within(dialog).getByLabelText(/Next status/), 'QUOTED');
  await user.click(within(dialog).getByRole('button', { name: 'Save updates' }));
  expect(await within(dialog).findByRole('alert')).toHaveTextContent('Retry your quote');
  expect(within(dialog).getByLabelText('Total quote (EUR)')).toHaveValue(150);
  failed = false;
  await user.click(within(dialog).getByRole('button', { name: 'Save updates' }));
  await waitFor(() => expect(writes.at(-1)).toMatchObject({ status: 'QUOTED', amountMinor: 15000 }));
  expect(await within(dialog).findByText('Customer acceptance confirmed')).toBeInTheDocument();
});

it('Staff dispatchers can use operational directories while admin management stays hidden', async () => {
  const { default: App } = await import('./App.jsx');
  const { saveSession } = await import('./api.js');
  const staff = { id: 'staff1', role: 'STAFF', fullName: 'Warehouse Staff' };
  saveSession('local-staff-session', staff);
  const fetched = [];
  vi.stubGlobal('fetch', vi.fn(async url => {
    const path = new URL(url).pathname; fetched.push(path);
    if (path === '/auth/me') return json({ user: staff });
    if (path === '/warehouse/directory/parcels') return json({ parcels: [{ ...parcel, origin: 'Omaha, NE, USA', destination: 'Lomé, Togo', status: 'RECEIVED', method: 'SEA', createdAt: '2026-10-24T09:00:00Z' }], total: 1 });
    if (path === '/warehouse/directory/customers') return json({ customers: [], total: 0 });
    throw new Error(`Unexpected staff route ${path}`);
  }));
  const user = userEvent.setup();
  render(<App />);
  expect(await screen.findByText(parcel.trackingId)).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Team & access', exact: true })).toBeNull();
  expect(screen.queryByRole('button', { name: 'Marketplace', exact: true })).toBeNull();
  expect(screen.queryByRole('button', { name: 'Locations', exact: true })).toBeNull();
  await user.click(screen.getByRole('button', { name: 'Customers', exact: true }));
  expect(await screen.findByText('No customers found')).toBeInTheDocument();
  expect(fetched.some(path => path.startsWith('/admin/'))).toBe(false);
});
