import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  clearSession,
  getSavedSession,
  request,
  saveSession,
  setApiBaseUrl,
  signIn,
} from './api.js';

describe('Admin API client', () => {
  beforeEach(() => {
    sessionStorage.clear();
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it('rejects a non-Admin login without saving a session', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            token: 'customer-token',
            user: { id: 'customer', role: 'CUSTOMER' },
          }),
          { status: 200, headers: { 'Content-Type': 'application/json' } },
        ),
      ),
    );

    await expect(signIn('user@example.com', 'password')).rejects.toThrow(
      'This account does not have Admin dashboard access.',
    );
    expect(sessionStorage.getItem('d2f_admin_token')).toBeNull();
  });

  it('stores only Admin sessions in the current tab', () => {
    saveSession('admin-token', {
      id: 'admin-1',
      role: 'ADMIN',
      fullName: 'D2F Admin',
    });
    expect(getSavedSession()).toEqual({
      token: 'admin-token',
      user: { id: 'admin-1', role: 'ADMIN', fullName: 'D2F Admin' },
    });

    clearSession();
    expect(getSavedSession()).toBeNull();
  });

  it('validates and saves an API origin without path segments', () => {
    expect(setApiBaseUrl('https://api.example.com/')).toBe(
      'https://api.example.com',
    );
    expect(localStorage.getItem('d2f_admin_api_url')).toBe(
      'https://api.example.com',
    );
    expect(() => setApiBaseUrl('javascript:alert(1)')).toThrow(
      'Enter a valid API origin',
    );
  });

  it('sends the session token only in the Authorization header', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    vi.stubGlobal('fetch', fetchMock);

    await request('/admin/overview', { token: 'secret-session-token' });

    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining('/admin/overview'),
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer secret-session-token',
        }),
      }),
    );
  });

  it('announces an expired session to the application', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: 'Session expired' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        }),
      ),
    );
    const onExpired = vi.fn();
    window.addEventListener('d2f-session-expired', onExpired);

    await expect(request('/auth/me')).rejects.toThrow('Session expired');
    expect(onExpired).toHaveBeenCalledOnce();

    window.removeEventListener('d2f-session-expired', onExpired);
  });
});
