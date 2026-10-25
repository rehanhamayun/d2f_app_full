import { useCallback, useState } from 'react';
import { Check } from 'lucide-react';
import { request } from './api.js';
import { Modal, useRemote, LoadState, place } from './operations-ui.jsx';
export function UserLocation({ token, user, notify, onSaved }) {
  const [open, setOpen] = useState(false);
  const close = useCallback(() => setOpen(false), []);
  return <><span>{user.location?.name || 'Unassigned'}</span><button className="text-button cell-sub" aria-label={`Assign location for ${user.fullName}`} onClick={() => setOpen(true)}>Assign location</button>{open && <Assignment token={token} user={user} onClose={close} onSaved={() => { close(); onSaved(); notify('Account location saved.'); }} />}</>;
}
function Assignment({ token, user, onClose, onSaved }) {
  const remote = useRemote('/warehouse/locations', token);
  const [location, setLocation] = useState(user.location?.id || ''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  async function save(e) { e.preventDefault(); setBusy(true); setError(''); try { await request(`/admin/users/${user.id}/location`, { token, method: 'PATCH', body: JSON.stringify({ locationId: location || null }) }); onSaved(); } catch (e) { setError(e.message); } finally { setBusy(false); } }
  return <Modal title="Assign account location" label={user.fullName} onClose={onClose} busy={busy}><LoadState remote={remote}><form className="modal-body invite-form ops-form" onSubmit={save}><label>Assigned facility<select value={location} onChange={e => setLocation(e.target.value)}><option value="">Unassigned</option>{remote.data?.map(l => <option key={l.id} value={l.id}>{l.name} · {place(l)}</option>)}</select></label>{error && <div className="alert error-alert" role="alert">{error}</div>}<button className="button primary full-button" disabled={busy}><Check size={16} /> Save assignment</button></form></LoadState></Modal>;
}
