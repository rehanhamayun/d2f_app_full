import { useCallback, useEffect, useState } from 'react';
import { Plus, ShoppingBag, ShoppingCart, ArrowRight, Check, ExternalLink, Star, Store, Warehouse } from 'lucide-react';
import { getApiBaseUrl, request } from './api.js';
import { Empty, Heading, Modal, Pagination, Pill, dateTime, human, useRemote, LoadState, CustomerPicker } from './operations-ui.jsx';
import { SellersPanel, CommissionPanel } from './sellers.jsx';

export function money(amount, currency = 'USD') { return amount == null ? 'Awaiting quote' : new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount / (currency === 'XOF' ? 1 : 100)); }
export function minorAmount(amount, currency) { const number = Number(amount); if (amount === '' || !Number.isFinite(number) || number < 0) return null; return Math.round(number * (currency === 'XOF' ? 1 : 100)); }

const COMMERCE_TABS = [
  { id: 'orders', label: 'Orders' },
  { id: 'products', label: 'Products' },
  { id: 'sellers', label: 'Sellers' },
  { id: 'commission', label: 'Commission' },
];

const sourceLabel = source => (source === 'APP' ? 'App order' : 'Admin record');
const sellerName = order => order.seller?.displayName || 'D2F catalog';

export function Commerce({ kind, token, notify, refreshKey }) {
  const marketplace = kind === 'MARKETPLACE';
  const [tab, setTab] = useState('orders');
  const [offset, setOffset] = useState(0), [createOrder, setCreateOrder] = useState(false), [product, setProduct] = useState(null), [selected, setSelected] = useState(null);
  const remote = useRemote(`/admin/commerce/${kind.toLowerCase()}?offset=${offset}`, token, refreshKey);
  const order = remote.data?.orders.find(o => o.id === selected);
  const closeOrder = useCallback(() => setCreateOrder(false), []), closeProduct = useCallback(() => setProduct(null), []), closeDetail = useCallback(() => setSelected(null), []);
  function changed(message) { remote.reload(); notify(message); }

  const ordersPanel = remote.data?.orders?.length ? (
    <div className="table-scroll"><table><thead><tr><th>{marketplace ? 'ORDER' : 'REQUEST'}</th><th>CUSTOMER</th>{marketplace && <th>SELLER</th>}<th>TOTAL</th>{marketplace && <th>COMM.</th>}<th>STATUS</th><th>PARCEL</th><th /></tr></thead><tbody>{remote.data.orders.map(o => <tr key={o.id}><td><button className="text-button ops-reference" onClick={() => setSelected(o.id)}>{o.title}</button><small className="cell-sub">{sourceLabel(o.source)} · Qty {o.quantity} · {dateTime(o.createdAt)}</small></td><td>{o.customer.displayName}</td>{marketplace && <td>{o.seller?.displayName || 'D2F catalog'}</td>}<td><b>{money(o.amountMinor, o.currency)}</b></td>{marketplace && <td>{o.commissionMinor != null ? money(o.commissionMinor, o.currency) : '—'}</td>}<td><Pill status={o.status} /></td><td>{o.parcel?.trackingId || 'Not linked'}</td><td><button className="icon-button" aria-label={`Open ${o.title}`} onClick={() => setSelected(o.id)}><ArrowRight size={16} /></button></td></tr>)}</tbody></table></div>
  ) : (
    <Empty title={marketplace ? 'No orders yet' : 'Your first request starts here'} text={marketplace ? 'Orders from the app and records you create appear here.' : 'Add a customer’s item and source link, then prepare their quote.'} />
  );

  const productsPanel = marketplace && <section className="panel ops-products"><div className="panel-heading"><div><h2>Product catalog</h2><p>D2F catalog and approved seller listings both appear here.</p></div><span className="ops-catalog-count">{remote.data?.products?.length || 0} products</span></div>{remote.data?.products?.length ? <div className="ops-product-grid">{remote.data.products.map(p => <ProductCard key={p.id} product={p} token={token} onEdit={() => setProduct(p)} onFeatured={featured => request(`/admin/commerce/products/${p.id}`, { token, method: 'PATCH', body: JSON.stringify({ featured }) }).then(() => remote.reload()).catch(err => notify(err.message))} />)}</div> : <Empty title="Build your catalog" text="Add the first product, then make it available for orders." />}</section>;

  return <>
    <Heading label="BUSINESS SERVICES" title={marketplace ? 'Marketplace' : 'Buy For Me'} text={marketplace ? 'Sellers, catalog and orders in one place — commission is agreed before the first sale.' : 'Keep purchase requests, quotes and shipping records in one place.'}>
      {marketplace && <button className="button secondary" onClick={() => setProduct({})}><Plus size={16} /> Add product</button>}
      <button className="button primary" onClick={() => setCreateOrder(true)}><Plus size={16} /> {marketplace ? 'Record order' : 'Add request'}</button>
    </Heading>
    <div className={`ops-service-banner ${marketplace ? 'ops-market-banner' : ''}`}><span className="ops-banner-icon">{marketplace ? <ShoppingBag size={28} /> : <ShoppingCart size={28} />}</span><div><b>{marketplace ? 'Products. Sellers. A clear path to shipping.' : 'Find it. Quote it. Send it.'}</b><p>{marketplace ? 'App orders arrive here automatically — review sellers, track commission, and link parcels when D2F ships.' : 'Record a total quote, confirm customer acceptance, then follow purchase and shipment.'}</p></div></div>
    {marketplace && <div className="tab-strip" role="tablist" aria-label="Marketplace sections">{COMMERCE_TABS.map(t => <button key={t.id} role="tab" aria-selected={tab === t.id} className={`tab-button ${tab === t.id ? 'tab-active' : ''}`} onClick={() => setTab(t.id)}>{t.label}</button>)}</div>}

    {!marketplace && <LoadState remote={remote}>
      <section className="panel table-panel"><div className="ops-section-heading"><h2>Purchase requests</h2><small>Administrative records · Manual updates</small></div>{ordersPanel}<Pagination total={remote.data?.total || 0} offset={offset} onPage={setOffset} /></section>
    </LoadState>}

    {marketplace && tab === 'orders' && <LoadState remote={remote}>
      <section className="panel table-panel"><div className="ops-section-heading"><h2>Customer orders</h2><small>App orders and manual records</small></div>{ordersPanel}<Pagination total={remote.data?.total || 0} offset={offset} onPage={setOffset} /></section>
    </LoadState>}
    {marketplace && tab === 'products' && <LoadState remote={remote}>{productsPanel}</LoadState>}
    {marketplace && tab === 'sellers' && <SellersPanel token={token} notify={notify} refreshKey={refreshKey} />}
    {marketplace && tab === 'commission' && <CommissionPanel token={token} refreshKey={refreshKey} />}

    {product && <ProductForm token={token} product={product} onClose={closeProduct} onSaved={() => { setProduct(null); changed('Product saved.'); }} />}
    {createOrder && <OrderForm token={token} kind={kind} products={remote.data?.products || []} onClose={closeOrder} onSaved={() => { setCreateOrder(false); setOffset(0); changed(marketplace ? 'Order recorded.' : 'Purchase request added.'); }} />}
    {order && <OrderDetail token={token} order={order} transitions={remote.data.transitions} onClose={closeDetail} onSaved={() => changed('Request updated.')} />}
  </>;
}

function ProductCard({ product, token, onEdit, onFeatured }) {
  const p = product;
  const [toggling, setToggling] = useState(false);
  async function toggleFeatured() {
    setToggling(true);
    try { await onFeatured(!p.featured); } finally { setToggling(false); }
  }
  return <article className="ops-product">
    <div className="ops-product-top"><span className="metric-icon coral"><ShoppingBag size={21} /></span><span className="ops-product-top-actions"><Pill status={p.isActive ? 'AVAILABLE' : 'DRAFT'} /><button className={`feature-toggle ${p.featured ? 'feature-on' : ''}`} aria-pressed={p.featured} aria-label={p.featured ? 'Remove from featured' : 'Feature this product'} title={p.featured ? 'Featured in the storefront' : 'Feature in the storefront'} onClick={toggleFeatured} disabled={toggling}><Star size={16} fill={p.featured ? 'currentColor' : 'none'} /></button></span></div>
    <small>{p.category}</small>
    <h3>{p.title}</h3>
    <p>{p.description || 'No description added.'}</p>
    <div className="ops-product-seller">{p.seller?.displayName ? <><Store size={12} /> {p.seller.displayName}</> : <><Warehouse size={12} /> D2F catalog</>}<span>{p.fulfillment === 'D2F' ? 'D2F fulfils' : 'Seller ships'}</span><span>{p.stockCount == null ? 'Stock n/a' : `Stock ${p.stockCount}`}</span></div>
    <div><b>{money(p.priceMinor, p.currency)}</b><button className="text-button" onClick={onEdit}>Edit product <ArrowRight size={13} /></button></div>
  </article>;
}

function ProductForm({ token, product, onClose, onSaved }) {
  const [form, setForm] = useState({ title: product.title || '', category: product.category || '', description: product.description || '', price: product.priceMinor == null ? '' : String(product.priceMinor / (product.currency === 'XOF' ? 1 : 100)), currency: product.currency || 'USD', isActive: product.isActive || false });
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const field = key => e => setForm({ ...form, [key]: e.target.value });
  async function save(e) {
    e.preventDefault(); setBusy(true); setError('');
    try { const payload = { ...form, priceMinor: minorAmount(form.price, form.currency) }; delete payload.price; if (!product.id && !payload.description.trim()) delete payload.description; await request(`/admin/commerce/products${product.id ? `/${product.id}` : ''}`, { token, method: product.id ? 'PATCH' : 'POST', body: JSON.stringify(payload) }); onSaved(); }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <Modal title={product.id ? 'Edit product' : 'Add a product'} label="MARKETPLACE CATALOG" onClose={onClose} busy={busy}><form className="modal-body invite-form ops-form" onSubmit={save}><label>Product title<input required maxLength={200} value={form.title} onChange={field('title')} /></label><label>Category<input required maxLength={80} value={form.category} onChange={field('category')} placeholder="e.g. Household goods" /></label><label>Description<textarea rows={3} maxLength={2000} value={form.description} onChange={field('description')} /></label><div className="form-row"><label>Unit price<input type="number" required min="0" step={form.currency === 'XOF' ? '1' : '.01'} value={form.price} onChange={field('price')} /></label><label>Currency<select value={form.currency} onChange={field('currency')}>{['USD', 'EUR', 'XOF'].map(c => <option key={c}>{c}</option>)}</select></label></div><label className="ops-checkbox"><input type="checkbox" checked={form.isActive} onChange={e => setForm({ ...form, isActive: e.target.checked })} /> Available for admin-recorded orders</label>{error && <div className="alert error-alert" role="alert">{error}</div>}<button className="button primary full-button" disabled={busy}><Check size={16} /> Save product</button></form></Modal>;
}
function OrderForm({ token, kind, products, onClose, onSaved }) {
  const marketplace = kind === 'MARKETPLACE';
  const [customerId, setCustomerId] = useState(''), [form, setForm] = useState({ title: '', sourceUrl: '', productId: '', quantity: 1, currency: 'USD', notes: '' });
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const field = key => e => setForm({ ...form, [key]: e.target.value });
  async function save(e) {
    e.preventDefault(); setBusy(true); setError('');
    try { const payload = { ...form, kind, customerId, quantity: Number(form.quantity) }; if (!payload.notes.trim()) delete payload.notes; await request('/admin/commerce/orders', { token, method: 'POST', body: JSON.stringify(payload) }); onSaved(); }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  const selectedProduct = products.find(p => p.id === form.productId);
  return <Modal title={marketplace ? 'Record an order' : 'Add a purchase request'} label={marketplace ? 'MARKETPLACE' : 'BUY FOR ME'} onClose={onClose} busy={busy}><form className="modal-body invite-form ops-form" onSubmit={save}><CustomerPicker token={token} value={customerId} onChange={setCustomerId} />{marketplace ? <label>Product<select required value={form.productId} onChange={field('productId')}><option value="">Choose an available product</option>{products.filter(p => p.isActive).map(p => <option key={p.id} value={p.id}>{p.title} · {money(p.priceMinor, p.currency)}</option>)}</select></label> : <><label>Requested item<input required maxLength={200} value={form.title} onChange={field('title')} /></label><label>Product link (optional)<input type="url" maxLength={2000} value={form.sourceUrl} onChange={field('sourceUrl')} placeholder="https://store.example/product" /></label></>}<div className="form-row"><label>Quantity<input required type="number" min="1" max="1000" step="1" value={form.quantity} onChange={field('quantity')} /></label>{!marketplace && <label>Quote currency<select value={form.currency} onChange={field('currency')}>{['USD', 'EUR', 'XOF'].map(c => <option key={c}>{c}</option>)}</select></label>}</div>{selectedProduct && <div className="ops-quote-total"><span>Order total</span><b>{money(selectedProduct.priceMinor * Number(form.quantity), selectedProduct.currency)}</b></div>}<label>Notes (optional)<textarea rows={3} maxLength={2000} value={form.notes} onChange={field('notes')} /></label>{error && <div className="alert error-alert" role="alert">{error}</div>}<button className="button primary full-button" disabled={busy}><Plus size={16} /> {marketplace ? 'Record order' : 'Add request'}</button></form></Modal>;
}

function OrderDetail({ token, order: o, transitions, onClose, onSaved }) {
  const [status, setStatus] = useState('');
  const [productCost, setProductCost] = useState(o.productCostMinor == null ? '' : String(o.productCostMinor / (o.currency === 'XOF' ? 1 : 100)));
  const [shippingCost, setShippingCost] = useState(o.shippingCostMinor == null ? '' : String(o.shippingCostMinor / (o.currency === 'XOF' ? 1 : 100)));
  const [tracking, setTracking] = useState(o.parcel?.trackingId || '');
  const [carrierRef, setCarrierRef] = useState(o.trackingRef || '');
  const [notes, setNotes] = useState(o.notes || '');
  const [customerMessage, setCustomerMessage] = useState('');
  const [updateStatus, setUpdateStatus] = useState('');
  const [deliveryService, setDeliveryService] = useState(o.deliveryService || '');
  const [shippingCarrier, setShippingCarrier] = useState(o.shippingCarrier || '');
  const [shippingTrackingNumber, setShippingTrackingNumber] = useState(o.shippingTrackingNumber || '');
  const [shippingLabelUrl, setShippingLabelUrl] = useState(o.shippingLabelUrl || '');
  const [updateImage, setUpdateImage] = useState(null);
  const [reviewNote, setReviewNote] = useState('');
  const [evidence, setEvidence] = useState(null);
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);

  useEffect(() => () => { if (evidence?.url) URL.revokeObjectURL(evidence.url); }, [evidence]);

  async function save(e) {
    e.preventDefault(); setBusy(true); setError('');
    try {
      const quoting = o.kind === 'BUY_FOR_ME' && ['REQUESTED', 'QUOTED'].includes(o.status);
      const payload = {
        ...(status ? { status } : {}),
        ...(tracking.trim() ? { trackingId: tracking.trim() } : {}),
        ...(carrierRef.trim() ? { trackingRef: carrierRef.trim() } : {}),
        notes: notes.trim(),
        ...(quoting && productCost !== '' && shippingCost !== ''
          ? {
              productCostMinor: minorAmount(productCost, o.currency),
              shippingCostMinor: minorAmount(shippingCost, o.currency),
            }
          : {}),
      };
      await request(`/admin/commerce/orders/${o.id}`, { token, method: 'PATCH', body: JSON.stringify(payload) });
      setStatus('');
      onSaved();
    }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  async function reviewPayment(submissionId, accepted) {
    setBusy(true); setError('');
    try {
      await request(`/admin/commerce/orders/${o.id}/payment-submissions/${submissionId}/review`, {
        token, method: 'POST', body: JSON.stringify({ accepted, note: reviewNote }),
      });
      setReviewNote('');
      onSaved();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  async function viewEvidence(submission) {
    try {
      const response = await fetch(`${getApiBaseUrl()}/admin/commerce/orders/${o.id}/payment-submissions/${submission.id}/image`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!response.ok) throw new Error('Payment evidence could not be loaded.');
      const url = URL.createObjectURL(await response.blob());
      setEvidence({ url, transactionId: submission.transactionId });
    } catch (e) { setError(e.message); }
  }
  async function postUpdate(e) {
    e.preventDefault(); setBusy(true); setError('');
    try {
      const values = {
        message: customerMessage.trim(),
        ...(updateStatus ? { status: updateStatus } : {}),
        ...(deliveryService ? { deliveryService } : {}),
        ...(shippingCarrier.trim() ? { shippingCarrier: shippingCarrier.trim() } : {}),
        ...(shippingTrackingNumber.trim() ? { shippingTrackingNumber: shippingTrackingNumber.trim() } : {}),
        ...(shippingLabelUrl.trim() ? { shippingLabelUrl: shippingLabelUrl.trim() } : {}),
      };
      if (updateImage) {
        const query = new URLSearchParams(values);
        const response = await fetch(`${getApiBaseUrl()}/admin/commerce/orders/${o.id}/updates?${query}`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': updateImage.type },
          body: updateImage,
        });
        const payload = await response.json().catch(() => null);
        if (!response.ok) throw new Error(payload?.error || 'The update could not be posted.');
      } else {
        await request(`/admin/commerce/orders/${o.id}/updates`, { token, method: 'POST', body: JSON.stringify(values) });
      }
      setCustomerMessage('');
      setUpdateStatus('');
      setUpdateImage(null);
      onSaved();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  const allowed = transitions[o.status] || [];
  const isMarketplaceApp = o.kind === 'MARKETPLACE' && o.source === 'APP';
  const commissionLabel = o.commissionBps != null ? `${(o.commissionBps / 100).toFixed(o.commissionBps % 100 === 0 ? 0 : 1)}%` : null;
  const quoting = o.kind === 'BUY_FOR_ME' && ['REQUESTED', 'QUOTED'].includes(o.status);
  const subtotal = productCost !== '' && shippingCost !== ''
    ? (minorAmount(productCost, o.currency) ?? 0) + (minorAmount(shippingCost, o.currency) ?? 0)
    : o.amountMinor;
  return <Modal title={o.title} label={o.kind === 'MARKETPLACE' ? 'MARKETPLACE ORDER' : 'BUY FOR ME REQUEST'} onClose={onClose} busy={busy}><div className="modal-body invite-form ops-form">
    <div className="detail-status"><span><small>CURRENT STATUS</small><Pill status={o.status} /></span><span><small>{o.kind === 'BUY_FOR_ME' ? 'SUBTOTAL' : 'ORDER TOTAL'}</small><b>{money(subtotal, o.currency)}</b></span></div>
    <div className="detail-grid"><div><small>Source</small><b>{o.source === 'APP' ? 'App (customer)' : 'Admin record'}</b></div><div><small>Customer</small><b>{o.customer.displayName}</b></div><div><small>Quantity</small><b>{o.quantity}</b></div><div><small>Created (Chicago time)</small><b>{dateTime(o.createdAt)}</b></div>{o.kind === 'MARKETPLACE' && <div><small>Seller</small><b>{sellerName(o)}</b></div>}{o.kind === 'MARKETPLACE' && <div><small>Commission</small><b>{o.commissionMinor != null ? `${money(o.commissionMinor, o.currency)} (${commissionLabel})` : '—'}</b></div>}<div><small>Parcel</small><b>{o.parcel?.trackingId || 'Not linked'}</b></div>{(o.kind === 'BUY_FOR_ME' && o.budgetMinor != null) && <div><small>Buyer budget</small><b>{money(o.budgetMinor, o.currency)}</b></div>}</div>
    {isMarketplaceApp && <div className="delivery-box"><small>DELIVERY</small><p><b>{o.deliveryPreference === 'D2F' ? 'D2F arranges delivery' : o.deliveryPreference === 'SELLER' ? 'Seller ships' : 'Not chosen'}</b></p><p>{[o.recipientName, o.recipientPhone].filter(Boolean).join(' · ')}</p><p>{[o.deliveryAddress, [o.deliveryCity, o.deliveryCountry].filter(Boolean).join(', ')].filter(Boolean).join(' — ')}</p></div>}
    {o.kind === 'BUY_FOR_ME' && <div className="delivery-box"><small>SHIP TO · CUSTOMER ADDRESS</small><p>{[o.deliveryAddress, o.deliveryCity, o.deliveryStateProvince, o.deliveryPostalCode, o.deliveryCountry].filter(Boolean).join(', ') || 'Address not provided'}</p></div>}
    {o.sourceUrl && <a className="text-button" href={o.sourceUrl} target="_blank" rel="noreferrer">Open product source <ExternalLink size={13} /></a>}
    {quoting && <><div className="form-row"><label>Product cost ({o.currency})<input type="number" min="0" step={o.currency === 'XOF' ? '1' : '.01'} value={productCost} onChange={e => setProductCost(e.target.value)} /></label><label>Shipping cost ({o.currency})<input type="number" min="0" step={o.currency === 'XOF' ? '1' : '.01'} value={shippingCost} onChange={e => setShippingCost(e.target.value)} /></label></div><div className="ops-quote-total"><span>Customer subtotal · product + shipping</span><b>{money(subtotal, o.currency)}</b></div></>}
    {allowed.filter(s => s !== 'PAYMENT_CONFIRMED').length > 0 && <label>Next status<select value={status} onChange={e => setStatus(e.target.value)}><option value="">Keep current status</option>{allowed.filter(s => s !== 'PAYMENT_CONFIRMED').map(s => <option key={s} value={s}>{s === 'ACCEPTED' ? 'Customer acceptance confirmed' : human(s)}</option>)}</select></label>}
    <label>Customer parcel tracking number<input maxLength={80} value={tracking} onChange={e => setTracking(e.target.value)} placeholder="Optional existing D2F parcel ID" /></label>
    <label>Carrier reference<input maxLength={120} value={carrierRef} onChange={e => setCarrierRef(e.target.value)} placeholder="e.g. carrier tracking reference" /></label>
    <label>Internal notes<textarea maxLength={2000} rows={3} value={notes} onChange={e => setNotes(e.target.value)} /></label>
    {error && <div className="alert error-alert" role="alert">{error}</div>}
    <button type="button" className="button primary full-button" disabled={busy} onClick={save}><Check size={16} /> Save quote / status</button>
    {o.kind === 'BUY_FOR_ME' && <section className="ops-update-panel"><h3>Payment proof</h3><p>Payment instructions: {o.paymentInstructions || 'Zelle: 01234567'}</p><p>Status: {human(o.paymentStatus || 'NOT_SUBMITTED')} · Transaction ID: {o.paymentTransactionId || 'Not submitted'}</p>
      {(o.paymentSubmissions || []).map(sub => <article key={sub.id}><b>{sub.method} · {human(sub.status)}</b><p>Transaction ID: {sub.transactionId}</p>{sub.reviewNote && <p>{sub.reviewNote}</p>}<button type="button" className="button secondary" onClick={() => viewEvidence(sub)}>View screenshot</button>{sub.status === 'PENDING' && <div className="form-row"><label>Correction note (only needed to reject)<input value={reviewNote} onChange={e => setReviewNote(e.target.value)} /></label><button type="button" className="button secondary" disabled={busy} onClick={() => reviewPayment(sub.id, false)}>Request correction</button><button type="button" className="button primary" disabled={busy} onClick={() => reviewPayment(sub.id, true)}>Verify payment</button></div>}</article>)}
      {evidence && <div className="ops-evidence"><button type="button" className="text-button" onClick={() => setEvidence(null)}>Close evidence</button><p>Transaction {evidence.transactionId}</p><img src={evidence.url} alt="Customer payment proof" /></div>}
    </section>}
    {o.kind === 'BUY_FOR_ME' && <form className="ops-update-panel" onSubmit={postUpdate}><h3>Post customer update & delivery details</h3><label>Message to customer<input maxLength={1000} value={customerMessage} onChange={e => setCustomerMessage(e.target.value)} placeholder="Your item was purchased…" /></label><label>Update order status<select value={updateStatus} onChange={e => setUpdateStatus(e.target.value)}><option value="">Keep current status</option>{allowed.filter(s => !['ACCEPTED', 'PAYMENT_CONFIRMED'].includes(s)).map(s => <option key={s} value={s}>{human(s)}</option>)}</select></label><label>Delivery service<select value={deliveryService} onChange={e => setDeliveryService(e.target.value)}><option value="">Keep current option</option>{[['D2F_CONNECT', 'D2F Connect'], ['AIR_CARGO', 'Air freight'], ['SEA', 'Sea freight'], ['AIR_TRAVELLER', 'Air traveller']].map(([value, name]) => <option key={value} value={value}>{name}</option>)}</select></label><div className="form-row"><label>Carrier<input value={shippingCarrier} onChange={e => setShippingCarrier(e.target.value)} /></label><label>Tracking number<input value={shippingTrackingNumber} onChange={e => setShippingTrackingNumber(e.target.value)} /></label></div><label>Shipping label URL<input type="url" value={shippingLabelUrl} onChange={e => setShippingLabelUrl(e.target.value)} placeholder="https://…" /></label><label>Attach update / shipping-label image<input type="file" accept="image/png,image/jpeg,image/webp" onChange={e => setUpdateImage(e.target.files?.[0] || null)} /></label><button className="button primary full-button" disabled={busy}>Send update & notify customer</button></form>}
    {o.kind === 'BUY_FOR_ME' && o.updates?.length > 0 && <section className="ops-update-panel"><h3>Customer update history</h3>{o.updates.map(update => <article key={update.id}><b>{update.status ? human(update.status) : 'D2F update'} · {dateTime(update.createdAt)}</b><p>{update.message}</p>{update.deliveryService && <p>{human(update.deliveryService)} {update.shippingCarrier ? `· ${update.shippingCarrier}` : ''} {update.shippingTrackingNumber ? `· ${update.shippingTrackingNumber}` : ''}</p>}{update.shippingLabelUrl && <a href={update.shippingLabelUrl} target="_blank" rel="noreferrer">Open shipping label</a>}{update.fileName && <span> · Image attached</span>}</article>)}</section>}
  </div></Modal>;
}
