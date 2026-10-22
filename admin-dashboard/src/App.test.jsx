import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import App from './App.jsx';

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('D2F Admin dashboard', () => {
  beforeEach(() => {
    sessionStorage.clear();
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it('does not grant dashboard access to a non-Admin account', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse({
          token: 'customer-token',
          user: { id: 'customer', role: 'CUSTOMER' },
        }),
      ),
    );
    const user = userEvent.setup();
    render(<App />);

    await user.type(screen.getByLabelText('Email address'), 'customer@example.com');
    await user.type(screen.getByLabelText('Password'), 'safe-password');
    await user.click(screen.getByRole('button', { name: /sign in to dashboard/i }));

    expect(
      await screen.findByText('This account does not have Admin dashboard access.'),
    ).toBeInTheDocument();
    expect(screen.queryByRole('navigation', { name: 'Admin dashboard' })).toBeNull();
    expect(sessionStorage.getItem('d2f_admin_token')).toBeNull();
  });

  it('shows live dashboard metrics after an Admin signs in', async () => {
    const previewParcels = Array.from({ length: 51 }, (_, index) => ({
      id: `parcel-${index + 1}`,
      trackingId: `D2F-OMA-${String(index + 1).padStart(5, '0')}`,
      customer: { displayName: `Customer ${index + 1}` },
      recipientName: `Recipient ${index + 1}`,
      origin: 'OMA',
      destination: 'LOM',
      method: 'AIR',
      status: 'IN_TRANSIT',
      createdAt: '2026-10-21T10:30:00Z',
    }));
    const fetchMock = vi.fn(async (url, options = {}) => {
      if (String(url).endsWith('/auth/login')) {
        return jsonResponse({
          token: 'admin-token',
          user: { id: 'admin-1', role: 'ADMIN', fullName: 'D2F Admin' },
        });
      }
      if (String(url).includes('/admin/overview')) {
        return jsonResponse({
          periodDays: 30,
          totalParcels: 42,
          periodParcels: 8,
          customerCount: 16,
          totalUsers: 20,
          activeUsers: 19,
          statusCounts: { RECEIVED: 12, IN_TRANSIT: 18, DELIVERED: 12 },
          methodCounts: { AIR: 20, SEA: 22 },
          parcelTrend: Array.from({ length: 30 }, (_, index) => ({
            date: `2026-10-${String(index + 1).padStart(2, '0')}`,
            count: index % 4,
          })),
          recentEvents: [],
          recentAudit: [],
        });
      }
      if (String(url).includes('/admin/parcels')) {
        const offset = Number(new URL(String(url)).searchParams.get('offset') || 0);
        return jsonResponse({
          parcels: previewParcels.slice(offset, offset + 50),
          total: previewParcels.length,
          limit: 50,
          offset,
        });
      }
      if (String(url).includes('/admin/customers')) {
        return jsonResponse({
          customers: [{ id: 'customer-profile-1', displayName: 'Amina Kossi', email: 'amina@example.com' }],
          total: 1,
          limit: 50,
          offset: 0,
        });
      }
      if (String(url).endsWith('/parcels') && options.method === 'POST') {
        return jsonResponse({
          id: 'new-parcel',
          trackingId: 'D2F-OMA-00052',
        }, 201);
      }
      if (String(url).endsWith('/auth/me')) {
        return jsonResponse({
          user: { id: 'admin-1', role: 'ADMIN', fullName: 'D2F Admin' },
        });
      }
      return jsonResponse({ ok: true, service: 'd2f-backend', database: 'connected' });
    });
    vi.stubGlobal('fetch', fetchMock);
    const user = userEvent.setup();
    render(<App />);

    await user.type(screen.getByLabelText('Email address'), 'admin@example.com');
    await user.type(screen.getByLabelText('Password'), 'safe-password');
    await user.click(screen.getByRole('button', { name: /sign in to dashboard/i }));

    expect(await screen.findByRole('heading', { name: /good day, administrator/i })).toBeInTheDocument();
    await waitFor(() =>
      expect(
        screen.getByText('42', { selector: '.metric-value' }),
      ).toBeInTheDocument(),
    );
    expect(screen.getByRole('navigation', { name: 'Admin dashboard' })).toBeInTheDocument();
    expect(sessionStorage.getItem('d2f_admin_token')).toBe('admin-token');

    fireEvent.click(
      within(screen.getByRole('navigation', { name: 'Admin dashboard' })).getByRole(
        'button',
        { name: 'Shipments' },
      ),
    );
    expect(await screen.findByRole('heading', { name: 'Shipments' })).toBeInTheDocument();
    expect(await screen.findByText('D2F-OMA-00001')).toBeInTheDocument();
    expect(screen.getByText('Showing 1–50 of 51')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(await screen.findByText('D2F-OMA-00051')).toBeInTheDocument();
    expect(screen.getByText('Showing 51–51 of 51')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Create shipment' }));
    await screen.findByRole('option', { name: /Amina Kossi/ });
    await user.selectOptions(await screen.findByLabelText('Customer'), 'customer-profile-1');
    await user.type(screen.getByLabelText('Recipient name'), 'Ama Lawson');
    await user.type(screen.getByLabelText('Weight (kg)'), '2');
    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Create shipment' }),
    );
    expect(await screen.findByText(/Shipment D2F-OMA-00052 created and shared with the D2F app/)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringMatching(/\/parcels$/),
      expect.objectContaining({ method: 'POST' }),
    );
  });
});
