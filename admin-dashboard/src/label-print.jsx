import React, { useState } from 'react';
import QRCode from 'qrcode';
import JsBarcode from 'jsbarcode';
import { request, getApiBaseUrl } from './api';

const LOCAL = 'http://127.0.0.1:18441';
const KEY = 'd2f_local_print_pairing';
const PENDING = 'd2f_pending_print_reports';
const text = value => String(value ?? '').trim();
export async function labelImage(parcel) {
  const canvas = document.createElement('canvas'); canvas.width = 1200; canvas.height = 1800;
  const g = canvas.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, 1200, 1800); g.fillStyle = '#000';
  const line = (value, y, size = 34, bold = false) => { g.font = `${bold ? 'bold ' : ''}${size}px Arial`; g.fillText(text(value), 55, y, 1090); };
  const wrapped = (value, y, size = 30, maxLines = 4) => {
    let lines;
    for (; size >= 18; size -= 2) {
      g.font = `${size}px Arial`; lines = []; let row = '';
      for (const word of text(value).split(/\s+/)) {
        if (g.measureText(row + ' ' + word).width > 1080 && row) { lines.push(row); row = word; } else row += (row ? ' ' : '') + word;
      }
      lines.push(row); if (lines.length <= maxLines) break;
    }
    if (lines.length > maxLines) throw new Error('The address is too long for a readable 4×6 label. Review its formatting before printing.');
    lines.forEach((row, index) => line(row, y + index * 42, size));
  };
  line('D2F SHIPPING', 100, 64, true); line('4 × 6 SHIPPING LABEL', 150, 26);
  line(parcel.trackingId, 230, 48, true);
  line(`SERVICE: ${parcel.serviceType || parcel.method}`, 290, 32, true);
  wrapped(`${parcel.origin} → ${parcel.destination}`, 350, 32, 2);
  g.fillRect(55, 425, 1090, 4);
  line('FROM', 480, 27, true); line(parcel.customer?.displayName || 'D2F customer', 525, 36, true);
  line(parcel.customer?.phone || '', 565, 30);
  wrapped(parcel.pickupAddress || parcel.customer?.address || parcel.origin, 610, 28, 3);
  line('SHIP TO', 770, 27, true); line(parcel.recipientName, 820, 40, true);
  line(parcel.recipientPhone || '', 865, 30);
  wrapped(parcel.recipientAddress || parcel.destination, 915, 34, 4);
  line(`DESTINATION: ${parcel.destination}`, 1115, 36, true);
  line(`${parcel.packageType || 'PACKAGE'} · ${parcel.weightKg} kg`, 1170, 30);
  const qr = document.createElement('canvas'); await QRCode.toCanvas(qr, parcel.trackingId, { width: 270, margin: 2, errorCorrectionLevel: 'M' }); g.drawImage(qr, 465, 1220, 270, 270);
  const barcode = document.createElement('canvas'); JsBarcode(barcode, parcel.trackingId, { format: 'CODE128', width: 3, height: 130, fontSize: 34, margin: 18 });
  g.drawImage(barcode, 75, 1510, 1050, 220);
  const png = canvas.toDataURL('image/png').split(',')[1];
  const bytes = Uint8Array.from(atob(png), c => c.charCodeAt(0));
  const labelHash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  return { png, labelHash };
}

export function LabelPrintPanel({ parcelId, token }) {
  const [open, setOpen] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState(''), [notice, setNotice] = useState('');
  const [key, setKey] = useState(() => sessionStorage.getItem(KEY) || '');
  const [printers, setPrinters] = useState([]), [printer, setPrinter] = useState('');
  const [image, setImage] = useState(null), [parcel, setParcel] = useState(null), [jobs, setJobs] = useState([]), [reason, setReason] = useState('');
  const ownerId = (() => { try { return `${new URL(getApiBaseUrl()).host}:${JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).id}`; } catch { return ''; } })();
  const owner = `${getApiBaseUrl()}:${ownerId}`;
  const local = async (path, body) => {
    const response = await fetch(LOCAL + path, { method: body ? 'POST' : 'GET', headers: { Authorization: `Bearer ${key}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(body ? 100000 : 15000) });
    const data = await response.json(); if (!response.ok) throw new Error(data.error || 'Local printing request failed.'); return data;
  };
  const run = async work => { if (busy) return; setBusy(true); setError(''); setNotice(''); try { await work(); } catch (e) { setError(e.message); } finally { setBusy(false); } };
  const pending = () => { try { return JSON.parse(sessionStorage.getItem(PENDING) || '[]'); } catch { return []; } };
  const sync = async rows => {
    const remaining = [];
    for (const row of rows) { if (row.owner !== owner) { remaining.push(row); continue; } try { await request('/label-print/history', { token, method: 'POST', body: JSON.stringify(row.report) }); } catch { remaining.push(row); } }
    sessionStorage.setItem(PENDING, JSON.stringify(remaining)); return remaining.filter(r => r.owner === owner).length;
  };
  const load = () => run(async () => {
    const data = await request(`/label-print/parcels/${parcelId}`, { token });
    setParcel(data); setImage(await labelImage(data));
    setJobs(await request(`/label-print/parcels/${parcelId}/history`, { token })); setOpen(true);
  });
  const connect = () => run(async () => {
    await local('/health'); const rows = await local('/printers'); setPrinters(rows); setPrinter(rows.includes(printer) ? printer : rows[0] || ''); sessionStorage.setItem(KEY, key);
    setNotice('Connected to the local Windows connector. Select the actual Brother 4×6 printer queue.');
  });
  const send = () => run(async () => {
    const localJobs = await local('/jobs');
    const prior = [...jobs, ...localJobs].some(j => j.parcelId === parcelId);
    if (prior && !reason.trim()) throw new Error('A previous job exists. Check physical output, then enter a reprint reason.');
    if (!window.confirm(`${prior ? 'Reprint' : 'Print'} one 4×6 label for ${parcel.trackingId} on ${printer}? Verify the loaded paper first.`)) return;
    const clientJobId = crypto.randomUUID();
    const report = await local('/jobs', { ...image, clientJobId, parcelId, trackingId: parcel.trackingId, printerName: printer, ownerId, reprint: prior, reason: reason.trim() });
    const { ownerId: _ownerId, trackingId: _trackingId, ...payload } = report;
    sessionStorage.setItem(PENDING, JSON.stringify([...pending(), { owner, report: payload }]));
    setJobs(j => [report, ...j]); const left = await sync(pending());
    setNotice(`${report.message}${left ? ' Cloud history pending sync; keep this tab open.' : ' Print history synced.'}`);
  });
  return <section className="connect-cargo"><h3>Shipping label · direct printing</h3><p>Windows: use the D2F local connector and installed Brother driver. Android: use Print Label in the D2F app.</p><button type="button" className="secondary-button" disabled={busy} onClick={load}>Print Label</button>{error && !open && <p role="alert">{error}</p>}
    {open && <div className="modal-backdrop" style={{ zIndex: 1000 }}><section className="connect-command" role="dialog" aria-modal="true" aria-label="Print shipping label" style={{ maxHeight: '90vh', overflow: 'auto' }}><header><h2>Print {parcel?.trackingId}</h2><button type="button" onClick={() => !busy && setOpen(false)} disabled={busy}>Close</button></header>
      {image && <img src={`data:image/png;base64,${image.png}`} alt="4 by 6 shipping label preview" style={{ width: 240, maxWidth: '100%', border: '1px solid #ddd' }} />}
      <p>Start <code>start.cmd</code> from the supplied Windows connector package. Allow the browser’s local network permission when requested. Set the Brother driver to the actual 4×6 roll.</p>
      <label>Local connector pairing key<input type="password" autoComplete="off" value={key} onChange={e => setKey(e.target.value)} /></label><button type="button" disabled={busy || !key} onClick={connect}>Connect local printer</button>
      <label>Installed Windows printer<select value={printer} onChange={e => setPrinter(e.target.value)}><option value="">Select a printer</option>{printers.map(p => <option key={p}>{p}</option>)}</select></label>
      <label>Reprint reason (required after any previous job)<input maxLength={500} value={reason} onChange={e => setReason(e.target.value)} /></label>
      {error && <p role="alert">{error}</p>}{notice && <p role="status">{notice}</p>}
      <button type="button" className="primary-button" disabled={busy || !image || !printer || !ownerId} onClick={send}>{busy ? 'Working…' : jobs.length ? 'Reprint label' : 'Print one label'}</button>
      <button type="button" disabled={busy} onClick={() => run(async () => { const rows = await local('/jobs'); const unsynced = rows.filter(r => r.ownerId === ownerId && r.status !== 'PRINTING').map(r => { const {ownerId: _o, trackingId: _t, ...report} = r; return {owner, report}; }); const left = await sync([...pending(), ...unsynced]); setNotice(left ? `${left} reports remain pending. Reconnect to the D2F API.` : 'History synced.'); })}>Sync print history</button>
      <p>QUEUED means Windows accepted the job. Verify output physically. Interrupted or uncertain jobs are never retried automatically. Printing does not change shipment status.</p>
      {jobs.map(j => <p key={j.clientJobId}>{j.printerName} · {j.status} · {j.message}</p>)}
    </section></div>}
  </section>;
}
