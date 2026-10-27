import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, expect, it, vi } from 'vitest';
import App from './App.jsx';
import { saveSession } from './api.js';

const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const original = {
  id: 'parcel-edit-1', trackingId: 'D2F000000000001', customerId: 'customer-original',
  customer: { id: 'customer-original', displayName: 'Current Customer' },
  recipientName: 'Original Recipient', recipientPhone: '+228 90000000', recipientAddress: 'Original address',
  packageType: 'BOX', weightKg: 2.5, origin: 'Omaha, NE, USA', destination: 'Lomé, Togo', method: 'SEA', notes: 'Original note',
  status: 'RECEIVED', createdAt: '2026-10-24T09:00:00Z', updatedAt: '2026-10-24T09:00:00Z',
  events: [{ id: 'event-1', status: 'RECEIVED', note: 'Registered at intake', createdAt: '2026-10-24T09:00:00Z' }],
};
beforeEach(() => { vi.restoreAllMocks(); localStorage.clear(); sessionStorage.clear(); });

function setup({ role = 'ADMIN', failSave = false, container = null } = {}) {
  const actor = { id: 'actor-1', role, fullName: 'Shipment Operator' };
  saveSession('local-test-session', actor);
  let parcel = { ...structuredClone(original), container }, failure = failSave;
  const writes = [], reads = [];
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => {
    const path = new URL(url).pathname;
    if (options.method === 'PATCH') {
      const body = JSON.parse(options.body); writes.push({ path, body });
      if (failure) return json({ error: 'This parcel has changed. Refresh before editing again.' }, 409);
      parcel = { ...parcel, ...body, customer: body.customerId === 'customer-new' ? { id: 'customer-new', displayName: 'Correct Customer' } : parcel.customer, updatedAt: '2026-10-26T09:00:00Z' };
      return json(parcel);
    }
    reads.push(path);
    if (path === '/auth/me') return json({ user: actor });
    if (path === '/admin/overview') return json({ totalParcels: 1, periodParcels: 1, customerCount: 2, totalUsers: 1, activeUsers: 1, statusCounts: {}, methodCounts: {}, parcelTrend: [], recentEvents: [], recentAudit: [] });
    if (path === '/admin/parcels' || path === '/warehouse/directory/parcels') return json({ parcels: [parcel], total: 1 });
    if (path === `/parcels/${parcel.id}`) return json(parcel);
    if (path === '/warehouse/locations') return json([{ id: 'loc-1', name: 'Omaha Warehouse', code: 'OMA-1', city: 'Omaha', country: 'United States' }]);
    // The existing customer deliberately sits outside the first page of search results.
    if (path === '/admin/customers') return json({ customers: [{ id: 'customer-new', displayName: 'Correct Customer' }], total: 55 });
    throw new Error(`Unexpected route ${path}`);
  }));
  return { writes, reads, allowSave: () => { failure = false; } };
}

async function openShipment(user, page = 'Shipments') {
  await user.click(screen.getByRole('button', { name: page, exact: true }));
  await user.click(await screen.findByText(original.trackingId));
  const details = screen.getByRole('dialog', { name: original.trackingId });
  await within(details).findByText('Registered at intake');
  return details;
}

it('Admin edits prefilled parcel inputs and sees saved details and refreshed rows', async () => {
  const { writes, reads } = setup();
  const user = userEvent.setup();
  render(<App />);
  const details = await openShipment(user);
  await user.click(within(details).getByRole('button', { name: 'Edit shipment' }));
  const edit = screen.getByRole('dialog', { name: 'Edit shipment' });
  expect(within(edit).getByLabelText('Recipient name')).toHaveValue('Original Recipient');
  expect(within(edit).getByLabelText('Delivery address')).toHaveValue('Original address');
  expect(within(edit).getByLabelText('Weight (kg)')).toHaveValue(2.5);
  await waitFor(() => expect(within(edit).getByLabelText('Customer')).toBeEnabled());
  expect(within(edit).getByLabelText('Customer')).toHaveValue('customer-original');
  await user.selectOptions(within(edit).getByLabelText('Customer'), 'customer-new');
  await user.clear(within(edit).getByLabelText('Recipient name'));
  await user.type(within(edit).getByLabelText('Recipient name'), 'Correct Recipient');
  await user.clear(within(edit).getByLabelText('Delivery address'));
  await user.type(within(edit).getByLabelText('Delivery address'), 'Correct address');
  await user.clear(within(edit).getByLabelText('Recipient phone'));
  await user.selectOptions(within(edit).getByLabelText('Package type'), 'BARREL');
  await user.clear(within(edit).getByLabelText('Weight (kg)'));
  await user.type(within(edit).getByLabelText('Weight (kg)'), '12.75');
  await user.selectOptions(within(edit).getByLabelText('Shipping method'), 'AIR');
  await user.clear(within(edit).getByLabelText('Destination'));
  await user.type(within(edit).getByLabelText('Destination'), 'Accra, Ghana');
  await user.click(within(edit).getByRole('button', { name: 'Save changes' }));
  const updated = await screen.findByRole('dialog', { name: original.trackingId });
  expect(within(updated).getByText('Correct Recipient')).toBeInTheDocument();
  expect(within(updated).getByText('Correct address')).toBeInTheDocument();
  expect(within(updated).getByText('Correct Customer')).toBeInTheDocument();
  expect(within(updated).getByText('Registered at intake')).toBeInTheDocument();
  expect(writes).toEqual([{ path: '/parcels/parcel-edit-1', body: {
    customerId: 'customer-new', recipientName: 'Correct Recipient', recipientAddress: 'Correct address', pickupAddress: '', recipientPhone: '',
    packageType: 'BARREL', weightKg: 12.75, method: 'AIR', origin: original.origin, destination: 'Accra, Ghana', notes: original.notes, updatedAt: original.updatedAt,
  } }]);
  await waitFor(() => expect(reads.filter(path => path === '/admin/parcels').length).toBeGreaterThan(1));
  await user.click(within(updated).getByRole('button', { name: 'Close shipment details' }));
  expect(await screen.findByText('Correct Recipient')).toBeInTheDocument();
});

it('Cancel discards the draft without saving, including from Bookings', async () => {
  const { writes } = setup();
  const user = userEvent.setup();
  render(<App />);
  const details = await openShipment(user, 'Bookings');
  await user.click(within(details).getByRole('button', { name: 'Edit shipment' }));
  const edit = screen.getByRole('dialog', { name: 'Edit shipment' });
  await user.clear(within(edit).getByLabelText('Recipient name'));
  await user.type(within(edit).getByLabelText('Recipient name'), 'Unsaved correction');
  await user.click(within(edit).getByRole('button', { name: 'Cancel' }));
  expect(writes).toHaveLength(0);
  expect(within(screen.getByRole('dialog', { name: original.trackingId })).getByText(original.recipientName)).toBeInTheDocument();
});

it('failed saves show an inline error and preserve the correction for retry', async () => {
  const api = setup({ failSave: true });
  const user = userEvent.setup();
  render(<App />);
  const details = await openShipment(user);
  await user.click(within(details).getByRole('button', { name: 'Edit shipment' }));
  const edit = screen.getByRole('dialog', { name: 'Edit shipment' });
  await user.clear(within(edit).getByLabelText('Recipient name'));
  await user.type(within(edit).getByLabelText('Recipient name'), 'Keep this correction');
  await waitFor(() => expect(within(edit).getByRole('button', { name: 'Save changes' })).toBeEnabled());
  await user.click(within(edit).getByRole('button', { name: 'Save changes' }));
  expect(await within(edit).findByRole('alert')).toHaveTextContent('This parcel has changed');
  expect(within(edit).getByLabelText('Recipient name')).toHaveValue('Keep this correction');
  api.allowSave();
  await user.click(within(edit).getByRole('button', { name: 'Save changes' }));
  expect(await screen.findByRole('dialog', { name: original.trackingId })).toHaveTextContent('Keep this correction');
});

it('container route restrictions leave recipient corrections available', async () => {
  setup({ container: { id: 'container-1', code: 'SEA-001', status: 'DEPARTED' } });
  const user = userEvent.setup();
  render(<App />);
  const details = await openShipment(user);
  await user.click(within(details).getByRole('button', { name: 'Edit shipment' }));
  const edit = screen.getByRole('dialog', { name: 'Edit shipment' });
  for (const field of ['Origin', 'Destination', 'Shipping method']) expect(within(edit).getByLabelText(field)).toBeDisabled();
  expect(within(edit).getByLabelText('Recipient name')).toBeEnabled();
  expect(within(edit).getByText('The departure manifest keeps the details recorded at departure.')).toBeInTheDocument();
});

it('Staff can review the shipment without access to Edit shipment', async () => {
  const { writes } = setup({ role: 'STAFF' });
  const user = userEvent.setup();
  render(<App />);
  const details = await openShipment(user);
  expect(within(details).queryByRole('button', { name: 'Edit shipment' })).toBeNull();
  expect(writes).toHaveLength(0);
});
