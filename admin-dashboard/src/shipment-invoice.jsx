import { useEffect, useState } from 'react';
import { request } from './api.js';

const amounts = (currency, value) => {
  const decimal = currency === 'XOF' ? 0 : 2;
  if (!(decimal ? /^\d+(?:\.\d{1,2})?$/.test(value) : /^\d+$/.test(value))) return null;
  return Math.round(Number(value) * 10 ** decimal);
};

export function ShipmentInvoice({ parcel, token, notify, onSaved }) {
  const [invoice, setInvoice] = useState(null);
  const [currency, setCurrency] = useState('USD');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const path = `/invoices/shipment/${encodeURIComponent(parcel.id)}`;

  useEffect(() => {
    if (!parcel.hasInvoice) return;
    let current = true;
    request(path, { token }).then(row => { if (current) setInvoice(row); })
      .catch(e => { if (current) setError(e.message); });
    return () => { current = false; };
  }, [parcel.hasInvoice, token, path]);

  async function submit(event) {
    event.preventDefault();
    if (busy || (parcel.hasInvoice && !invoice)) return;
    setBusy(true);
    setError('');
    try {
      const data = new FormData(event.currentTarget);
      const paymentReference = data.get('paymentReference')?.trim() || undefined;
      const amountMinor = invoice ? undefined : amounts(currency, data.get('amount').trim());
      if (amountMinor === null || (amountMinor != null && (!Number.isSafeInteger(amountMinor) || amountMinor > 1_000_000_000))) {
        throw new Error('Enter the agreed amount in the selected currency.');
      }
      await request(path, { token, method: 'PUT', body: JSON.stringify({ amountMinor, currency, paymentReference }) });
      setInvoice(await request(path, { token }));
      notify(paymentReference ? 'Verified payment recorded.' : 'Shipment invoice issued.');
      await onSaved();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  return <section className="connect-cargo">
    <h3>Shipment invoice</h3>
    {error && <p className="connect-error" role="alert">{error}</p>}
    {parcel.hasInvoice && !invoice ? !error && <p role="status">Loading invoice…</p> : (
      <>
        {invoice && <p><strong>{invoice.number}</strong>{' · '}
          {new Intl.NumberFormat(undefined, { style: 'currency', currency: invoice.currency }).format(invoice.totalMinor / (invoice.currency === 'XOF' ? 1 : 100))}
          {' · '}{invoice.status}
        </p>}
        {invoice?.status !== 'Paid' && <details>
          <summary>{invoice ? 'Record full payment' : 'Issue invoice for agreed charges'}</summary>
          <form key={invoice?.number || 'create'} onSubmit={submit}>
            {!invoice && <div className="form-row">
              <label>Agreed shipping charge<input name="amount" required inputMode="decimal" maxLength={13} /></label>
              <label>Currency<select value={currency} onChange={e => setCurrency(e.target.value)}>
                <option>USD</option><option>EUR</option><option>XOF</option>
              </select></label>
            </div>}
            {invoice && <label>Verified payment reference<input name="paymentReference" required maxLength={120} /></label>}
            <button className="button secondary" disabled={busy}>{busy ? 'Saving…' : invoice ? 'Record full payment' : 'Issue shipment invoice'}</button>
          </form>
        </details>}
      </>
    )}
  </section>;
}
