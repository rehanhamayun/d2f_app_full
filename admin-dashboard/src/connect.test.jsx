import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, expect, it, vi } from 'vitest';
import { ConnectOperations, AirCargoReference } from './connect.jsx';
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const booking = { id: 'b1', category: 'CLOTHING', quantity: 1, declaredValueMinor: 20000, internationalFeeMinor: 12500, domesticCostMinor: 2200, handoverMode: 'DOMESTIC_SHIPPING', domesticStatus: 'AWAITING_ADMIN_REVIEW', senderCity: 'Dallas, Texas', senderAddress: 'Private return address', assignments: [], parcel: { id: 'p1', trackingId: 'D2F000000000101', origin: 'New York, USA', destination: 'Lomé, Togo', status: 'REQUESTED', notes: 'Clothing in a sealed box', weightKg: 5, recipientName: 'Kossi Morgan', recipientAddress: 'Lomé, Togo', customer: { displayName: 'Mary Morgan', email: 'mary@example.test', phone: '+12145550111' }, events: [] } };
beforeEach(() => { vi.restoreAllMocks(); localStorage.clear(); sessionStorage.clear(); });
it('staff reviews complete Connect details and separate domestic fees without admin financial controls', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => json({ bookings: [booking], trips: [], rates: [], locations: [] })));
  render(<ConnectOperations token="test" notify={vi.fn()} refreshKey={0} isAdmin={false} />);
  await userEvent.click(await screen.findByRole('button', { name: 'Review D2F000000000101' }));
  expect(screen.getByText((_, node) => node.tagName === 'DD' && node.textContent.includes('Private return address'))).toBeInTheDocument(); expect(screen.getByText('Clothing in a sealed box')).toBeInTheDocument(); expect(screen.getByText('Domestic carrier cost')).toBeInTheDocument(); expect(screen.getByText('$147.00')).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Set final quotation' })).toBeNull(); expect(screen.queryByRole('button', { name: 'Directional rates' })).toBeNull();
  expect(screen.getByRole('button', { name: 'Verify contents & actual weight' })).toBeInTheDocument();
});
it('quotation errors preserve entered values and fees use integer cents', async () => {
  const writes = [];
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => { if (options.method === 'POST') { writes.push(JSON.parse(options.body)); return json({ error: 'The agreed price is locked.' }, 409); } return json({ bookings: [booking], trips: [], rates: [], locations: [] }); }));
  const user = userEvent.setup(); render(<ConnectOperations token="test" notify={vi.fn()} refreshKey={0} isAdmin />);
  await user.click(await screen.findByRole('button', { name: 'Review D2F000000000101' })); await user.click(screen.getByRole('button', { name: 'Set final quotation' }));
  const dialog = screen.getByRole('dialog', { name: 'Set separate domestic and international fees' });
  await user.type(within(dialog).getByLabelText('International fee (USD)'), '125'); await user.type(within(dialog).getByLabelText('Domestic carrier cost (USD)'), '22.50'); await user.type(within(dialog).getByLabelText('Quotation explanation'), 'Clothing fee and UPS domestic shipping'); await user.click(within(dialog).getByRole('button', { name: 'Confirm & record' }));
  expect(await within(dialog).findByRole('alert')).toHaveTextContent('agreed price is locked'); expect(within(dialog).getByLabelText('Domestic carrier cost (USD)')).toHaveValue(22.5); expect(writes[0].internationalFeeMinor).toBe(12500); expect(writes[0].domesticCostMinor).toBe(2250);
});
it('Air Cargo saves AWB as a separate carrier reference and never offers it for Connect', async () => {
  const writes = [], saved = vi.fn(); vi.stubGlobal('fetch', vi.fn(async (url, options) => { writes.push({ path: new URL(url).pathname, data: JSON.parse(options.body) }); return json({}); }));
  const user = userEvent.setup(); const { rerender } = render(<AirCargoReference parcel={{ id: 'p1', trackingId: 'D2F000000000101', serviceType: 'AIR_CARGO' }} token="test" notify={vi.fn()} onSaved={saved} />);
  await user.type(screen.getByLabelText('AWB / Air Waybill number'), '123-12345678'); await user.type(screen.getByLabelText('Airline / cargo carrier'), 'Example Cargo'); await user.click(screen.getByRole('button', { name: 'Save Air Cargo references' })); await waitFor(() => expect(saved).toHaveBeenCalled());
  expect(writes[0].path).toBe('/parcels/p1/air-cargo'); expect(writes[0].data.awbNumber).toBe('123-12345678'); expect(writes[0].data.trackingId).toBeUndefined();
  rerender(<AirCargoReference parcel={{ id: 'p1', serviceType: 'AIR_TRAVELLER', method: 'AIR' }} token="test" notify={vi.fn()} />); expect(screen.queryByLabelText('AWB / Air Waybill number')).toBeNull();
});
