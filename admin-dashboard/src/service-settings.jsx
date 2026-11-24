import { useState } from 'react';
import { request } from './api.js';
import { Heading, LoadState, Modal, useRemote, dateTime } from './operations-ui.jsx';

const services = '/admin/commerce/services';

export function Retailers({ token, onClose, notify }) {
  const remote = useRemote(`${services}/retailers`, token);
  return <Modal title="Popular retailers" onClose={onClose} wide>
    <div className="modal-body"><LoadState remote={remote}>
      {remote.data && <RetailerForm token={token} original={remote.data} onSaved={() => { notify('Retailer links published.'); onClose(); }} />}
    </LoadState></div>
  </Modal>;
}

function RetailerForm({ token, original, onSaved }) {
  const [stores, setStores] = useState(original);
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  const update = (index, fields) => setStores(stores.map((store, i) => index === i ? { ...store, ...fields } : store));
  function move(index, offset) {
    const rows = [...stores];
    [rows[index], rows[index + offset]] = [rows[index + offset], rows[index]];
    setStores(rows);
  }
  async function save(event) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      await request(`${services}/retailers`, { token, method: 'PUT', body: JSON.stringify({ stores, previous: original }) });
      onSaved();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  }
  return <form className="invite-form" onSubmit={save}>
    {stores.map((store, i) => <fieldset className="connect-cargo" key={i}>
      <legend>{store.name || 'New retailer'}</legend>
      <div className="form-row">
        <label>Name<input required maxLength={60} value={store.name} onChange={e => update(i, { name: e.target.value })} /></label>
        <label>Country<select value={store.country} onChange={e => update(i, { country: e.target.value })}><option value="US">United States</option><option value="FR">France</option></select></label>
      </div>
      <label>Official site<input type="url" required value={store.url} onChange={e => update(i, { url: e.target.value })} /></label>
      <label>Logo URL<input type="url" value={store.logoUrl ?? ''} onChange={e => update(i, { logoUrl: e.target.value })} /></label>
      <div className="heading-actions">
        <label className="checkbox-label"><input type="checkbox" checked={store.enabled} onChange={e => update(i, { enabled: e.target.checked })} /> Visible in app</label>
        <button type="button" className="button secondary" disabled={i === 0} onClick={() => move(i, -1)}>Move up</button>
        <button type="button" className="button secondary" disabled={i === stores.length - 1} onClick={() => move(i, 1)}>Move down</button>
      </div>
    </fieldset>)}
    {error && <p role="alert">{error}</p>}
    <div className="heading-actions">
      <button type="button" className="button secondary" onClick={() => setStores([...stores, { name: '', country: 'US', url: '', logoUrl: '', enabled: true }])}>Add retailer</button>
      <button className="button primary" disabled={busy}>Publish retailer links</button>
    </div>
  </form>;
}

export function ShipForMeSettings({ token, notify }) {
  const agreements = useRemote(`${services}/agreements?serviceType=SHIP_FOR_ME`, token);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  async function publish(event) {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.currentTarget));
    setBusy(true);
    setError('');
    try {
      await request(`${services}/agreements`, { token, method: 'POST', body: JSON.stringify({ ...data, serviceType: 'SHIP_FOR_ME' }) });
      agreements.reload();
      setEditing(false);
      notify('Ship For Me terms published.');
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  }
  return <>
    <Heading title="Ship For Me" text="Publish the terms customers must accept before registering a purchase.">
      <button className="button primary" onClick={() => { setError(''); setEditing(true); }}>New terms version</button>
    </Heading>
    <LoadState remote={agreements}><section className="panel table-panel">
      {!agreements.data?.length && <p className="modal-body">No terms have been published.</p>}
      {agreements.data?.map(agreement => <div className="modal-body" key={agreement.id}>
        <h3>{agreement.title} · {agreement.version}</h3>
        <p>{agreement.isActive ? 'Published' : 'Inactive'} · {dateTime(agreement.effectiveFrom)} · {agreement._count.acceptances} accepted</p>
        <details><summary>Read full terms</summary><p style={{ whiteSpace: 'pre-wrap' }}>{agreement.content}</p></details>
      </div>)}
    </section></LoadState>
    {editing && <Modal title="Publish Ship For Me terms" onClose={() => setEditing(false)} busy={busy}>
      <form className="modal-body invite-form" onSubmit={publish}>
        <label>Version<input name="version" required maxLength={50} placeholder="ship-for-me-v1" /></label>
        <label>Title<input name="title" required maxLength={200} /></label>
        <label>Approved terms<textarea name="content" required maxLength={10000} rows={12} /></label>
        <p>Customers must accept this version before registering a new purchase.</p>
        {error && <p role="alert">{error}</p>}
        <button className="button primary" disabled={busy}>Publish terms</button>
      </form>
    </Modal>}
  </>;
}
