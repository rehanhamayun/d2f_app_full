import React, { useRef, useState } from 'react';
import QRCode from 'qrcode';
import JsBarcode from 'jsbarcode';
import { request, getApiBaseUrl } from './api';

const LOCAL = 'http://127.0.0.1:18441';
const KEY = 'd2f_local_print_pairing';
const PENDING = 'd2f_pending_print_reports';
const text = value => String(value ?? '').trim();
export function physicalLabels(parcel) {
  if (!parcel.items?.length) return [{ code: parcel.trackingId, position: 1, count: 1 }];
  return parcel.items.flatMap((item, index) => item.packageCode && !item.notCollectedReason
    ? [{ code: item.packageCode, position: index + 1, count: parcel.items.length, item }]
    : []);
}

export async function labelImage(parcel, { code, position, count, item }) {
  const canvas = document.createElement('canvas');
  canvas.width = 1200;
  canvas.height = 1800;
  const g = canvas.getContext('2d');
  g.fillStyle = '#fff';
  g.fillRect(0, 0, 1200, 1800);
  g.fillStyle = '#000';
  const line = (value, x, y, size, width, bold = false) => {
    g.font = `${bold ? 'bold ' : ''}${size}px Arial`;
    g.fillText(text(value), x, y, width);
  };
  const block = (value, x, y, width, size, rows, step, bold = false) => {
    let lines = [];
    for (; size >= 16; size -= 2) {
      g.font = `${bold ? 'bold ' : ''}${size}px Arial`;
      lines = [];
      let row = '';
      for (const word of text(value).split(/\s+/)) {
        const next = row ? `${row} ${word}` : word;
        if (row && g.measureText(next).width > width) { lines.push(row); row = word; }
        else row = next;
      }
      if (row) lines.push(row);
      if (lines.length <= rows) break;
    }
    const visible = lines.slice(0, rows);
    if (lines.length > rows) visible[rows - 1] += '…';
    visible.forEach((row, i) => line(row, x, y + i * step, size, width, bold));
  };
  const address = (title, person, phone, place, x) => {
    line(title, x, 1105, 30, 510, true);
    block(person, x, 1162, 510, 44, 2, 46, true);
    line(phone, x, 1250, 37, 510);
    block(place, x, 1300, 510, 34, 4, 39);
  };

  line('D2F SHIPPING', 63, 125, 72, 735, true);
  const method = (parcel.serviceType || parcel.method || '').replaceAll('_', ' ');
  line(method, 869, 114, 33, 268, true);
  g.fillRect(63, 165, 1074, 6);
  line('DESTINATION', 63, 248, 34, 720);
  block(parcel.destination?.toUpperCase(), 63, 362, 782, 88, 2, 90, true);
  g.fillRect(878, 221, 259, 239);
  g.fillStyle = '#fff';
  line(`${position} / ${count}`, 910, 333, 65, 195, true);
  line('PACKAGE', 912, 406, 31, 190);
  g.fillStyle = '#000';
  g.fillRect(63, 519, 1074, 3);
  line('PACKAGE TRACKING', 63, 596, 34, 1074);
  line(code, 63, 693, 79, 1074, true);

  const barcode = document.createElement('canvas');
  JsBarcode(barcode, code, { format: 'CODE128', width: 4, height: 190, displayValue: false, margin: 44 });
  const barcodeWidth = Math.min(1074, barcode.width);
  g.imageSmoothingEnabled = false;
  g.drawImage(barcode, (1200 - barcodeWidth) / 2, 752, barcodeWidth, 237);
  g.fillRect(63, 1030, 1074, 3);
  address('FROM', parcel.customer?.displayName, parcel.customer?.phone, parcel.origin, 63);
  address('SHIP TO', parcel.recipientName, parcel.recipientPhone, parcel.recipientAddress || parcel.destination, 625);

  g.fillRect(63, 1450, 1074, 3);
  line('SHIPMENT GROUP', 63, 1520, 30, 700);
  line(parcel.trackingId, 63, 1584, 55, 700, true);
  line((item?.type || parcel.packageType || 'PACKAGE').replaceAll('_', ' '), 63, 1645, 34, 700);
  const verified = item?.verifiedWeightKg ?? (count === 1 ? (parcel.connectBooking?.verifiedWeightKg ?? parcel.verifiedWeightKg) : null);
  const weight = verified ?? item?.weightKg ?? (count === 1 ? parcel.weightKg : null);
  line(weight == null ? 'WEIGHT NOT RECORDED' : `${verified != null || (parcel.warehouseReceivedAt && !parcel.restrictionsAcknowledgedAt) ? 'VERIFIED' : 'RECORDED'} WEIGHT  ${weight} kg`, 63, 1697, 34, 700);

  const qr = document.createElement('canvas');
  await QRCode.toCanvas(qr, code, { width: 278, margin: 4, errorCorrectionLevel: 'M' });
  g.drawImage(qr, 853, 1467, 278, 278);
  const png = canvas.toDataURL('image/png').split(',')[1];
  const bytes = Uint8Array.from(atob(png), c => c.charCodeAt(0));
  const labelHash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  return { png, labelHash, code };
}

export function RecordPhysicalPackages({ parcel, token, onSaved }) {
  const [rows, setRows] = useState([{}, {}]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const types = ['BOX', 'SUITCASE', 'BARREL', 'TV', 'APPLIANCE', 'FURNITURE', 'PALLET', 'VEHICLE', 'DOCUMENTS', 'OTHER'];
  if (parcel.items?.length || !parcel.warehouseReceivedAt || !parcel.locationId || parcel.containerId ||
      !['RECEIVED', 'PROCESSING', 'READY_FOR_LOADING'].includes(parcel.status) || parcel.serviceType === 'AIR_TRAVELLER') return null;

  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await request(`/parcels/${parcel.id}/physical-packages`, {
        token, method: 'POST',
        body: JSON.stringify({ physicalPackages: rows.map(row => ({ type: row.type || parcel.packageType, weightKg: Number(row.weight) })) }),
      });
      await onSaved();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  function setRow(index, patch) {
    setRows(current => current.map((row, i) => i === index ? { ...row, ...patch } : row));
  }

  return <details className="connect-cargo">
    <summary>Record multiple physical packages</summary>
    <p>Use this when a shipment with one existing label has multiple packages at the warehouse.</p>
    <form onSubmit={submit}>
      {rows.map((row, index) => <fieldset key={index} className="form-row">
        <legend>Package {index + 1}</legend>
        <label>Type<select value={row.type || parcel.packageType} onChange={e => setRow(index, { type: e.target.value })}>
          {types.map(type => <option key={type}>{type}</option>)}
        </select></label>
        <label>Measured weight (kg)<input type="number" min=".001" max="10000" step="any" required value={row.weight || ''} onChange={e => setRow(index, { weight: e.target.value })} /></label>
      </fieldset>)}
      {error && <p role="alert">{error}</p>}
      <div className="heading-actions">
        <button className="button secondary" type="button" disabled={busy || rows.length <= 2} onClick={() => setRows(current => current.slice(0, -1))}>Remove last package</button>
        <button className="button secondary" type="button" disabled={busy || rows.length >= 20} onClick={() => setRows(current => [...current, {}])}>Add package</button>
        <button className="button primary" disabled={busy}>{busy ? 'Saving…' : 'Record and enable package labels'}</button>
      </div>
    </form>
  </details>;
}

export function LabelPrintPanel({ parcelId, token }) {
  const [open, setOpen] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState(''), [notice, setNotice] = useState('');
  const active = useRef(false);
  const browserPrintFrame = useRef(null);
  const [packagePrinting, setPackagePrinting] = useState(false);
  const [connection, setConnection] = useState('Disconnected');
  const [key, setKey] = useState(() => sessionStorage.getItem(KEY) || '');
  const [printers, setPrinters] = useState([]), [printer, setPrinter] = useState('');
  const [images, setImages] = useState([]), [parcel, setParcel] = useState(null), [jobs, setJobs] = useState([]), [reason, setReason] = useState('');
  const ownerId = (() => { try { return `${new URL(getApiBaseUrl()).host}:${JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).id}`; } catch { return ''; } })();
  const owner = `${getApiBaseUrl()}:${ownerId}`;
  const local = async (path, body) => {
    if (!key.trim()) throw new Error('Enter the pairing key from the Windows connector console.');
    let response;
    try { response = await fetch(LOCAL + path, { credentials: 'omit', method: body ? 'POST' : 'GET', headers: { Authorization: `Bearer ${key.trim()}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(body ? 100000 : 15000) });
    } catch {
      setConnection('Connector unreachable');
      setPrinters([]);
      setPrinter('');
      throw new Error(body
        ? 'Windows did not return a print result. Check the printer and sync history before reprinting.'
        : 'Start start.cmd on this Windows PC and allow local network access in the browser’s site settings, then reconnect.');
    }
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        setConnection('Pairing required');
        setPrinters([]);
        setPrinter('');
      }
      throw new Error(data.error || 'Local printing request failed.');
    }
    return data;
  };
  const run = async work => { if (active.current) return; active.current = true; setBusy(true); setError(''); setNotice(''); try { await work(); } catch (e) { setError(e.message); } finally { active.current = false; setBusy(false); } };
  const pending = () => { try { return JSON.parse(sessionStorage.getItem(PENDING) || '[]'); } catch { return []; } };
  const sync = async rows => {
    const remaining = [];
    for (const row of rows) { if (row.owner !== owner) { remaining.push(row); continue; } try { await request('/label-print/history', { token, method: 'POST', body: JSON.stringify(row.report) }); } catch { remaining.push(row); } }
    sessionStorage.setItem(PENDING, JSON.stringify(remaining)); return remaining.filter(r => r.owner === owner).length;
  };
  const load = () => run(async () => {
    const data = await request(`/label-print/parcels/${parcelId}`, { token });
    const labels = physicalLabels(data);
    if (!labels.length) throw new Error('Labels are available after D2F records physical custody.');
    const generated = await Promise.all(labels.map(label => labelImage(data, label)));
    setParcel(data);
    setImages(generated);
    setOpen(true);
  });
  function printFrame(title, styles) {
    if (browserPrintFrame.current) return null;
    setError('');
    const frame = document.createElement('iframe');
    browserPrintFrame.current = frame;
    frame.title = title;
    frame.style.cssText = 'position:fixed;width:0;height:0;border:0;';
    document.body.append(frame);
    const cleanup = () => {
      if (browserPrintFrame.current !== frame) return;
      clearTimeout(expiry);
      frame.remove();
      browserPrintFrame.current = null;
    };
    const expiry = setTimeout(cleanup, 60000);
    const doc = frame.contentDocument;
    const style = doc.createElement('style');
    style.textContent = '@page {size:4in 6in;margin:0} html,body {margin:0;width:4in}' + styles;
    doc.head.append(style);
    const print = () => {
      if (browserPrintFrame.current !== frame) return;
      frame.contentWindow.addEventListener('afterprint', cleanup, { once: true });
      try { frame.contentWindow.print(); }
      catch { cleanup(); setError('The print dialog could not open. Try again in Chrome or Edge.'); }
    };
    return { doc, print, cleanup };
  }

  function printInBrowser() {
    const out = printFrame('4 × 6 shipping label', 'img {display:block;width:4in;height:6in;break-inside:avoid} img:not(:last-child) {break-after:page}');
    if (!out) return;
    const { doc, print, cleanup } = out;
    let remaining = images.length;
    for (const image of images) {
      const label = doc.createElement('img');
      label.alt = `Shipping label for ${image.code}`;
      label.onload = () => { if (--remaining === 0) print(); };
      label.onerror = () => { cleanup(); setError('A label could not load for printing. Close the preview and try again.'); };
      label.src = `data:image/png;base64,${image.png}`;
      doc.body.append(label);
    }
  }

  function printReceipt() {
    const out = printFrame('4 × 6 shipment intake receipt', `
      *{box-sizing:border-box}body{font:10pt Arial,sans-serif;color:#000}
      article{width:4in;height:6in;padding:.22in;break-inside:avoid;position:relative}
      article:not(:last-child){break-after:page}h1,h2,p{margin:0 0 5px}h1{font-size:18pt}
      h2{font-size:14pt}hr{border:0;border-top:1px solid #000;margin:8px 0}
      .contacts{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:9px 0}
      .contacts p{font-size:8.5pt;line-height:1.2;overflow-wrap:anywhere;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:6;overflow:hidden}
      table{border-collapse:collapse;width:100%;font-size:8.5pt}th,td{padding:4px;text-align:left;border-bottom:1px solid #000}
      th:last-child,td:last-child{text-align:right}td{overflow-wrap:anywhere}
      table tr{break-inside:avoid}footer{position:absolute;bottom:.23in;left:.22in;right:.22in;border-top:1px solid #000;padding-top:5px;font-size:8pt}
    `);
    if (!out) return;
    const { doc, print } = out;
    const add = (parent, tag, value) => {
      const node = doc.createElement(tag);
      if (value != null) node.textContent = value;
      parent.append(node);
      return node;
    };
    const rows = parcel.items?.length ? parcel.items.map((item, index) => ({
      sequence: `${index + 1} / ${parcel.items.length}`,
      code: item.packageCode, type: item.type, weight: item.verifiedWeightKg ?? item.weightKg,
      verified: item.verifiedWeightKg != null, missed: item.notCollectedReason,
    })) : [{
      sequence: '1 / 1', code: parcel.trackingId, type: parcel.packageType,
      weight: parcel.verifiedWeightKg ?? parcel.weightKg, verified: parcel.verifiedWeightKg != null,
    }];
    const pages = Math.ceil(rows.length / 4);
    for (let page = 0; page < pages; page++) {
      const article = add(doc.body, 'article');
      add(article, 'h1', 'D2F SHIPPING');
      add(article, 'p', `Shipment intake receipt · ${(parcel.serviceType || parcel.method || '').replaceAll('_', ' ')}`);
      add(article, 'hr');
      add(article, 'small', 'DESTINATION');
      add(article, 'h2', parcel.destination?.toUpperCase());
      add(article, 'p', `Shipment group / tracking · ${parcel.trackingId}`);
      const date = parcel.warehouseReceivedAt || parcel.createdAt;
      if (date) add(article, 'p', `Intake · ${new Date(date).toLocaleDateString()}`);
      add(article, 'p', `${rows.filter(row => !row.missed).length} of ${rows.length} packages received · ${parcel.verifiedWeightKg != null ? 'Verified total' : 'Recorded weight'} ${parcel.verifiedWeightKg ?? parcel.weightKg} kg`);
      if (page === 0) {
        const contacts = add(article, 'div');
        contacts.className = 'contacts';
        for (const [label, name, phone, address] of [
          ['FROM', parcel.customer?.displayName, parcel.customer?.phone, parcel.origin],
          ['SHIP TO', parcel.recipientName, parcel.recipientPhone, parcel.recipientAddress || parcel.destination],
        ]) {
          const party = add(contacts, 'div');
          add(party, 'strong', label);
          for (const value of [name, phone, address]) if (value) add(party, 'p', value);
        }
      }
      const table = add(article, 'table');
      const head = add(table, 'tr');
      for (const label of ['Package', 'Tracking / type', 'Weight']) add(head, 'th', label);
      for (const row of rows.slice(page * 4, (page + 1) * 4)) {
        const tr = add(table, 'tr');
        add(tr, 'td', row.sequence);
        const identity = add(tr, 'td', row.code || 'Pending');
        add(identity, 'br');
        identity.append(doc.createTextNode(row.type || 'Package'));
        add(tr, 'td', row.missed ? 'Not received' : row.weight == null ? 'Not recorded' : `${row.weight} kg ${row.verified ? 'verified' : 'recorded'}`);
      }
      add(article, 'footer', `${parcel.trackingId} · Page ${page + 1} of ${pages}`);
    }
    print();
  }

  const connect = () => run(async () => {
    const health = await local('/health'); setPackagePrinting(health.packagePrinting === true); const rows = await local('/printers'); setPrinters(rows); setPrinter(rows.includes(printer) ? printer : rows[0] || ''); sessionStorage.setItem(KEY, key);
    setConnection('Paired');
    setNotice(rows.length ? 'Select the Windows printer queue configured for the 4×6 roll.' : 'No installed Windows printer queues found. Install the printer driver, then reconnect.');
  });
  const send = () => run(async () => {
    const [localJobs, history] = await Promise.all([
      local('/jobs'),
      request(`/label-print/parcels/${parcelId}/history`, { token }),
    ]);
    if (localJobs.some(j => j.parcelId === parcelId && j.status === 'PRINTING')) throw new Error('Windows is still processing this label. Wait and sync print history.');
    const prior = [...jobs, ...history, ...localJobs].some(j => j.parcelId === parcelId);
    if (prior && !reason.trim()) throw new Error('A previous job exists. Check physical output, then enter a reprint reason.');
    if (images.length > 1 && !packagePrinting) throw new Error('Update the Windows connector for multiple labels, or use browser printing.');
    if (!window.confirm(`${prior ? 'Reprint' : 'Print'} ${images.length} × 4×6 ${images.length === 1 ? 'label' : 'labels'} for ${parcel.trackingId} on ${printer}?`)) return;
    const reports = [];
    for (const { png, labelHash, code } of images) {
      const report = await local('/jobs', { png, labelHash, clientJobId: crypto.randomUUID(), parcelId, trackingId: code, printerName: printer, ownerId, reprint: prior, reason: reason.trim() });
      const { ownerId: _ownerId, trackingId: _trackingId, ...payload } = report;
      sessionStorage.setItem(PENDING, JSON.stringify([...pending(), { owner, report: payload }]));
      reports.push(report);
      setJobs(rows => [report, ...rows.filter(row => row.clientJobId !== report.clientJobId)]);
      if (report.status !== 'QUEUED' && report.status !== 'COMPLETED') break;
    }
    const left = await sync(pending());
    const summary = reports.length === 1 ? reports[0].message : `${reports.filter(r => ['QUEUED', 'COMPLETED'].includes(r.status)).length} of ${images.length} labels accepted by Windows.`;
    setNotice(`${summary}${left ? ' Cloud history pending sync; keep this tab open.' : ' Print history synced.'}`);
  });
  return <section className="connect-cargo">
    <h3>Shipping label</h3>
    <button type="button" className="secondary-button" disabled={busy} onClick={load}>Print Label</button>
    {error && !open && <p role="alert">{error}</p>}
    {open && <div className="modal-backdrop" style={{ zIndex: 1000 }}>
      <section className="connect-command" role="dialog" aria-modal="true" aria-label="Print shipping label" style={{ maxHeight: '90vh', overflow: 'auto' }}>
        <header><h2>Print {parcel?.trackingId}</h2><button type="button" className="secondary-button" onClick={() => setOpen(false)} disabled={busy}>Close</button></header>
        <div className="shipping-label-toolbar">
          <button type="button" className="primary-button" onClick={printInBrowser} disabled={busy}>{images.length === 1 ? 'Print 4 × 6 label' : `Print ${images.length} labels · 4 × 6`}</button>
          {(parcel.warehouseReceivedAt || parcel.status === 'RECEIVED' || parcel.connectBooking?.originReceivedAt) &&
            <button type="button" className="secondary-button" onClick={printReceipt} disabled={busy}>Print intake receipt</button>}
        </div>
        <p>Select your printer, 4 × 6-inch portrait paper, actual size, and one copy per page.</p>
        {error && <p role="alert">{error}</p>}
        <div className="shipping-label-previews">{images.map(image => <img key={image.code} src={`data:image/png;base64,${image.png}`} alt={`4 by 6 label for ${image.code}`} />)}</div>
        <details>
          <summary>Direct printing and print history (optional)</summary>
          <p>For connector print history, run <code>start.cmd</code> on the Windows PC. Open the pairing-key file shown in the console privately, enter the key below, and allow local network access when prompted.</p>
          <label>Local connector pairing key<input type="password" autoComplete="off" value={key} onChange={e => { setKey(e.target.value); sessionStorage.removeItem(KEY); setConnection('Pairing required'); setPrinters([]); setPrinter(''); }} /></label>
          <button type="button" className="secondary-button" disabled={busy || !key} onClick={connect}>Connect local printer</button>
          <p role="status">Connector: {connection}</p>
          <label>Installed Windows printer<select value={printer} onChange={e => setPrinter(e.target.value)}><option value="">Select a printer</option>{printers.map(p => <option key={p}>{p}</option>)}</select></label>
          <label>Reprint reason (required after any previous job)<input maxLength={500} value={reason} onChange={e => setReason(e.target.value)} /></label>
          {notice && <p role="status">{notice}</p>}
          <button type="button" className="secondary-button" disabled={busy || !printer || !ownerId} onClick={send}>{busy ? 'Working…' : jobs.length ? 'Reprint label' : images.length === 1 ? 'Print one label' : `Print ${images.length} labels`}</button>
          <button type="button" className="secondary-button" disabled={busy} onClick={() => run(async () => { const pendingCount = await sync(pending()); let rows; try { rows = await local('/jobs'); } catch (e) { setNotice(pendingCount ? `${pendingCount} reports still await API sync.` : 'Saved browser reports synced. Connect to Windows for the printer’s history.'); throw e; } const unsynced = rows.filter(r => r.ownerId === ownerId && r.status !== 'PRINTING').map(r => { const {ownerId: _o, trackingId: _t, ...report} = r; return {owner, report}; }); const left = await sync([...pending(), ...unsynced]); setJobs(await request(`/label-print/parcels/${parcelId}/history`, { token })); setNotice(left ? `${left} reports remain pending. Reconnect to the D2F API.` : 'History synced.'); })}>Sync print history</button>
          <p>QUEUED means Windows accepted the job. Check the printer before reprinting an uncertain job.</p>
          {jobs.map(j => <p key={j.clientJobId}>{j.printerName} · {j.status} · {j.message}</p>)}
        </details>
      </section>
    </div>}
  </section>;
}
