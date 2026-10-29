import { useEffect, useState } from 'react';
import { request } from './api.js';

export function CustodyActions({ parcel, token, onSaved, isAdmin = false }) {
  const [locations, setLocations] = useState([]), [drivers, setDrivers] = useState([]);
  const [mode, setMode] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const [verified, setVerified] = useState([]);
  const [when, setWhen] = useState(() => {
    const raw = parcel.pickupScheduledAt || parcel.pickupPreferredAt;
    if (!raw) return '';
    const d = new Date(raw); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0,16);
  });
  const pickup = parcel.deliveryMode === 'PICKUP';
  const scheduling = pickup && ['REQUESTED','PICKUP_SCHEDULED'].includes(parcel.status);
  const legacyPickup = parcel.status === 'PICKED_UP' && !parcel.pickupConfirmedAt;
  const intake = !parcel.warehouseReceivedAt && (['RECEIVED','PROCESSING'].includes(parcel.status) || pickup && parcel.status === 'PICKED_UP' && parcel.pickupConfirmedAt || !pickup && parcel.status === 'REQUESTED');
  useEffect(() => { let live = true; Promise.all([request('/warehouse/locations', { token }), request('/parcels/drivers/active', { token })]).then(([l,d]) => { if(live){ setLocations(l); setDrivers(d); } }).catch(e => { if(live) setError(e.message); }); return () => { live=false; }; }, [token]);
  const dispatch = ['ARRIVED_LOME','ARRIVED_DESTINATION','READY_FOR_PICKUP'].includes(parcel.status);
  if (parcel.serviceType === 'AIR_TRAVELLER' || !scheduling && !intake && !dispatch && !legacyPickup && parcel.status !== 'PICKUP_SCHEDULED') return null;
  const items = (parcel.items || []).filter(i => !i.notCollectedReason);
  async function submit(e) {
    e.preventDefault(); setBusy(true); setError('');
    const f = new FormData(e.currentTarget);
    try {
      const body = { locationId: f.get('locationId'), confirmed: f.get('confirmed') === 'on' };
      if (mode === 'legacy') Object.assign(body, { pickupDriverId: f.get('pickupDriverId') });
      else if (mode === 'dispatch') Object.assign(body, { status: 'OUT_FOR_DELIVERY', deliveryDriverId: f.get('pickupDriverId'), note: 'Destination facility confirmed dispatch to the assigned delivery driver.' });
      else if (mode === 'schedule') Object.assign(body, { pickupDriverId: f.get('pickupDriverId'), pickupScheduledAt: new Date(when).toISOString() });
      else Object.assign(body, { scannedTrackingId: f.get('scannedTrackingId'), verifiedItemIds: verified, note: f.get('note') });
      await request(`/parcels/${parcel.id}/${mode === 'schedule' ? 'pickup-schedule' : mode === 'dispatch' ? 'events' : mode === 'legacy' ? 'pickup-verification' : 'warehouse-intake'}`, { token, method:'POST', body:JSON.stringify(body) });
      setMode(''); await onSaved();
    } catch(e) { setError(e.message); } finally { setBusy(false); }
  }
  return <section className="connect-cargo"><h3>{pickup ? 'Pickup & warehouse custody' : 'Customer drop-off & warehouse intake'}</h3>
    <p>{legacyPickup ? 'An older pickup is recorded without assigned-driver evidence. Admin must assign verification; the driver confirms custody before warehouse receipt.' : parcel.status === 'PICKUP_SCHEDULED' ? 'The assigned driver confirms physical collection in the mobile app. This parcel is still awaiting collection; it is not at the warehouse.' : pickup && parcel.status === 'PICKED_UP' ? 'Driver collection is confirmed. The warehouse must scan and verify the parcel separately.' : !pickup && parcel.status === 'REQUESTED' ? 'Awaiting customer drop-off. Warehouse staff must verify physical receipt.' : 'Confirm custody using the actual handover and receiving facility.'}</p>
    {parcel.pickupPreferredAt && <p>Customer preferred pickup: {new Date(parcel.pickupPreferredAt).toLocaleString()}</p>}
    {parcel.pickupScheduledAt && <p>D2F confirmed appointment: {new Date(parcel.pickupScheduledAt).toLocaleString()}</p>}
    {!mode && <div className="heading-actions">{scheduling && <button className="button primary" onClick={() => setMode('schedule')}>{parcel.status === 'PICKUP_SCHEDULED' ? 'Manage pickup appointment' : 'Schedule pickup & assign driver'}</button>}{isAdmin && parcel.status === 'PICKED_UP' && !parcel.pickupConfirmedAt && <button className="button secondary" onClick={() => setMode('legacy')}>Assign driver verification for recorded pickup</button>}{dispatch && <button className="button primary" onClick={() => setMode('dispatch')}>Assign driver & dispatch delivery</button>}{intake && <button className="button primary" onClick={() => setMode('intake')}>Scan & verify warehouse receipt</button>}</div>}
    {mode && <form onSubmit={submit}><div className="form-grid"><label>{mode === 'schedule' ? 'Planned receiving warehouse' : 'Actual receiving warehouse'}<select name="locationId" required defaultValue={(mode === 'dispatch' ? parcel.locationId : parcel.pickupTargetLocationId || parcel.locationId) || ''}><option value="">Choose facility</option>{locations.map(l => <option key={l.id} value={l.id}>{l.name} · {l.city}, {l.country}</option>)}</select></label>
      {mode === 'schedule' || mode === 'dispatch' || mode === 'legacy' ? <><label>Assigned pickup driver<select name="pickupDriverId" required defaultValue={parcel.pickupDriverId || ''}><option value="">Choose active driver</option>{drivers.map(d => <option value={d.id} key={d.id}>{d.fullName}</option>)}</select></label>{mode === 'schedule' && <label>Confirmed pickup appointment · local time<input type="datetime-local" required value={when} onChange={e => setWhen(e.target.value)} /></label>}{!drivers.length && <p>Add/invite an active Driver through Team & access before confirming a pickup.</p>}</> : <><label>Scan or enter D2F tracking number<input name="scannedTrackingId" required autoComplete="off" placeholder="Scan the label in front of you" /></label><label>Warehouse inspection & condition<textarea name="note" required maxLength="1000" /></label></>}
    </div>{mode === 'intake' && items.length > 0 && <fieldset><legend>Verify each physical package received</legend>{items.map(i => <label className="checkbox-label" key={i.id}><input type="checkbox" checked={verified.includes(i.id)} onChange={e => setVerified(v => e.target.checked ? [...v,i.id] : v.filter(x => x !== i.id))} />{i.packageCode || i.type} · {i.name} · {i.quantity} contents units</label>)}</fieldset>}
    <label className="checkbox-label"><input name="confirmed" type="checkbox" required />{mode === 'schedule' ? 'D2F confirmed this appointment, driver and receiving warehouse with the customer.' : mode === 'legacy' ? 'Assign driver verification for the existing pickup record; this does not confirm warehouse receipt.' : mode === 'dispatch' ? 'I physically handed these goods to the assigned delivery driver at this destination facility.' : 'I physically scanned, inspected and verified these goods at this receiving warehouse.'}</label>
    {error && <p className="alert error-alert" role="alert">{error}</p>}<div className="heading-actions"><button type="button" className="button secondary" disabled={busy} onClick={() => setMode('')}>Cancel</button><button className="button primary" disabled={busy || mode === 'intake' && verified.length !== items.length}>{busy ? 'Saving…' : mode === 'schedule' ? 'Confirm pickup appointment' : mode === 'dispatch' ? 'Confirm dispatch' : mode === 'legacy' ? 'Assign driver verification' : 'Confirm warehouse receipt'}</button></div></form>}
    {!mode && error && <p className="alert error-alert" role="alert">{error}</p>}
  </section>;
}
