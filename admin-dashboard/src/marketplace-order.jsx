import { useState } from 'react';
import { request } from './api.js';
import { LoadState, dateTime, human, useRemote } from './operations-ui.jsx';

const money = (amount, currency) => amount == null ? '—' : new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount / (currency === 'XOF' ? 1 : 100));

export function MarketplaceOrderControls({ order, token, onSaved }) {
  const history = useRemote(`/admin/commerce/orders/${order.id}/history`, token);
  const [command, setCommand] = useState('');
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  const [verified, setVerified] = useState(true);
  const [issueType, setIssueType] = useState('RETURN');
  const [resolution, setResolution] = useState('RESOLVED');
  const marketplacePath = `/admin/commerce/orders/${order.id}`;
  const issue = order.marketplaceIssues?.find(row => row.id === command);
  const multiplier = order.currency === 'XOF' ? 1 : 100;
  function open(next) {
    setCommand(next);
    setResolution('RESOLVED');
    setError('');
  }
  async function save(event) {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.currentTarget));
    if ('amount' in data) {
      data.amountMinor = Math.round(Number(data.amount) * multiplier);
      delete data.amount;
    }
    if (command === 'payment') Object.assign(data, { verified, currency: order.currency });
    if (issue) data.status = resolution;
    const path = command === 'payment' ? 'marketplace-payment' : issue ? `issues/${issue.id}` : 'issues';
    setBusy(true);
    setError('');
    try {
      await request(`${marketplacePath}/${path}`, { token, method: issue ? 'PATCH' : 'POST', body: JSON.stringify(data) });
      setCommand('');
      history.reload();
      onSaved();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  }
  return <section className="connect-cargo">
    <h3>Payment, exceptions and history</h3>
    <p>Payment {human(order.paymentStatus)} · Fulfillment {human(order.status)}</p>
    {order.marketplacePaymentMethod && <p>{human(order.marketplacePaymentMethod)} · {order.paymentTransactionId} · {dateTime(order.marketplacePaymentVerifiedAt)}{order.marketplacePaymentNote ? ` · ${order.marketplacePaymentNote}` : ''}</p>}
    <dl>
      <dt>Order subtotal and total payable</dt><dd>{money(order.amountMinor, order.currency)}</dd>
      <dt>D2F commission</dt><dd>{money(order.commissionMinor ?? 0, order.currency)}</dd>
      <dt>D2F fulfillment fee</dt><dd>{money(order.fulfillmentFeeMinor ?? 0, order.currency)}</dd>
      <dt>Delivery fee</dt><dd>{money(order.deliveryFeeMinor ?? 0, order.currency)}</dd>
      <dt>Payment processing fee</dt><dd>{money(0, order.currency)}</dd>
      <dt>Seller payout before refunds</dt><dd>{money(order.sellerNetMinor, order.currency)}</dd>
    </dl>
    {order.marketplaceInvoice && <p>Invoice {order.marketplaceInvoice.number} · {order.marketplaceInvoice.issuer}</p>}
    <div className="heading-actions">
      {order.status === 'ACCEPTED' && order.paymentStatus !== 'VERIFIED' && <button className="button secondary" onClick={() => open('payment')}>Review marketplace payment</button>}
      {order.status !== 'REQUESTED' && <button className="button secondary" onClick={() => { setIssueType('DISPUTE'); open('issue'); }}>Open order issue</button>}
    </div>
    {order.marketplaceIssues?.map(row => <div key={row.id}>
      <p><b>{human(row.type)} · {human(row.status)}</b> · {row.reason}{row.resolution && ` · ${row.resolution}`}</p>
      {row.amountMinor != null && <p>{money(row.amountMinor, order.currency)} refund recorded</p>}
      {row.status === 'OPEN' && <button className="button secondary" onClick={() => open(row.id)}>Review {human(row.type).toLowerCase()}</button>}
    </div>)}
    {command && <form className="invite-form" onSubmit={save}>
      {command === 'payment' ? <>
        <label>Decision<select value={verified ? 'verified' : 'rejected'} onChange={e => setVerified(e.target.value === 'verified')}><option value="verified">Verify payment received</option><option value="rejected">Reject payment</option></select></label>
        <label>Method<select name="method" required><option value="">Choose method</option><option value="BANK_TRANSFER">Bank transfer</option><option value="MOBILE_MONEY">Mobile money</option><option value="CASH">Cash</option><option value="CARD">Card</option></select></label>
        <label>Transaction or receipt reference<input name="reference" required maxLength={120} /></label>
        {verified && <label>Received amount ({order.currency})<input name="amount" type="number" required min="0" step={1 / multiplier} defaultValue={order.amountMinor / multiplier} /></label>}
        <label>{verified ? 'Verification note (optional)' : 'Reason for rejection'}<textarea name="note" required={!verified} maxLength={500} /></label>
      </> : issue ? <>
        <label>Outcome<select value={resolution} onChange={e => setResolution(e.target.value)}><option value="RESOLVED">{issue.type === 'REFUND' ? 'Confirm refund was paid' : 'Resolve issue'}</option><option value="DECLINED">Decline request</option></select></label>
        <label>Resolution<textarea name="resolution" required maxLength={1000} /></label>
        {issue.type === 'REFUND' && resolution === 'RESOLVED' && <>
          <label>Amount actually returned ({order.currency})<input name="amount" type="number" required min={1 / multiplier} step={1 / multiplier} /></label>
          <label>External refund transaction reference<input name="reference" required maxLength={120} /></label>
        </>}
      </> : <>
        <label>Issue type<select name="type" value={issueType} onChange={e => setIssueType(e.target.value)}>
          <option value="DISPUTE">Dispute</option>
          {['DELIVERED', 'COMPLETED'].includes(order.status) && <option value="RETURN">Return</option>}
          {order.paymentStatus === 'VERIFIED' && <option value="REFUND">Refund request</option>}
        </select></label>
        <label>Reason<textarea name="reason" required maxLength={1000} /></label>
        <label>Evidence reference (optional)<input name="evidence" maxLength={500} /></label>
      </>}
      {error && <p role="alert">{error}</p>}
      <div className="heading-actions"><button type="button" className="button secondary" disabled={busy} onClick={() => open('')}>Cancel</button><button className="button primary" disabled={busy}>Save decision</button></div>
    </form>}
    <details><summary>Audit history</summary><LoadState remote={history}>
      {history.data?.map(row => <p key={row.id}><b>{human(row.action)}</b> · {row.actor?.fullName || 'System'} · {dateTime(row.createdAt)}<small className="cell-sub">{row.detail}</small></p>)}
    </LoadState></details>
  </section>;
}

export const fulfillmentMethods = {
  SELLER_DELIVERY: 'Seller delivery',
  D2F_DELIVERY: 'D2F delivery',
  EXTERNAL_CARRIER: 'External carrier',
  CUSTOMER_PICKUP: 'Customer pickup',
};
