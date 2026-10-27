const API_DEFAULT =
  import.meta.env.VITE_API_BASE_URL ||
  'https://d2f-api-production.up.railway.app';
const API_OVERRIDE_KEY = 'd2f_admin_api_url';
const TOKEN_KEY = 'd2f_admin_token';
const USER_KEY = 'd2f_admin_user';

export function getApiBaseUrl() {
  return (
    localStorage.getItem(API_OVERRIDE_KEY) ||
    API_DEFAULT
  ).replace(/\/+$/, '');
}

export function setApiBaseUrl(value) {
  const clean = value.trim().replace(/\/+$/, '');
  if (!/^https?:\/\/[^/]+(?::\d+)?$/i.test(clean)) {
    throw new Error('Enter a valid API origin, such as https://api.example.com.');
  }
  localStorage.setItem(API_OVERRIDE_KEY, clean);
  return clean;
}

export function getSavedSession() {
  try {
    const token = sessionStorage.getItem(TOKEN_KEY);
    const user = JSON.parse(sessionStorage.getItem(USER_KEY) || 'null');
    return token && ['ADMIN', 'STAFF'].includes(user?.role) ? { token, user } : null;
  } catch {
    clearSession();
    return null;
  }
}

export function saveSession(token, user) {
  sessionStorage.setItem(TOKEN_KEY, token);
  sessionStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearSession() {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(USER_KEY);
}

export async function request(path, { token, ...options } = {}) {
  let response;
  try {
    response = await fetch(`${getApiBaseUrl()}${path}`, {
      ...options,
      headers: {
        Accept: 'application/json',
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...options.headers,
      },
    });
  } catch {
    throw new Error(
      `Cannot reach the API at ${getApiBaseUrl()}. Check the backend URL and service status.`,
    );
  }

  const contentType = response.headers.get('content-type') || '';
  const payload = contentType.includes('application/json')
    ? await response.json()
    : null;
  if (!response.ok) {
    if (response.status === 401) {
      window.dispatchEvent(new Event('d2f-session-expired'));
    }
    throw new Error(
      payload?.error ||
        `The API request failed (${response.status}). Please try again.`,
    );
  }
  return payload;
}

export async function signIn(email, password) {
  const session = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email: email.trim(), password }),
  });
  if (!['ADMIN', 'STAFF'].includes(session?.user?.role) || !session.token) {
    throw new Error('This account does not have Admin dashboard access.');
  }
  saveSession(session.token, session.user);
  return session;
}
