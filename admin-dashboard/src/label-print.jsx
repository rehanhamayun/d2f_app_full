import React, { useRef, useState } from 'react';
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
  const scale = Math.min(1, 1050 / barcode.width);
  const width = Math.round(barcode.width * scale);
  g.imageSmoothingEnabled = false;
  g.drawImage(barcode, Math.round((1200 - width) / 2), 1510, width, Math.round(barcode.height * scale));
  const png = canvas.toDataURL('image/png').split(',')[1];
  const bytes = Uint8Array.from(atob(png), c => c.charCodeAt(0));
  const labelHash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  return { png, labelHash };
}

export function LabelPrintPanel({ parcelId, token }) {
  const [open, setOpen] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState(''), [notice, setNotice] = useState('');
  const active = useRef(false);
  const browserPrintFrame = useRef(null);
  const [connection, setConnection] = useState('Disconnected');
  const [key, setKey] = useState(() => sessionStorage.getItem(KEY) || '');
  const [printers, setPrinters] = useState([]), [printer, setPrinter] = useState('');
  const [image, setImage] = useState(null), [parcel, setParcel] = useState(null), [jobs, setJobs] = useState([]), [reason, setReason] = useState('');
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
    const generated = await labelImage(data);
    setParcel(data);
    setImage(generated);
    setOpen(true);
  });
  function printInBrowser() {
    if (browserPrintFrame.current) return;
    setError('');
    const frame = document.createElement('iframe');
    browserPrintFrame.current = frame;
    frame.title = '4 × 6 shipping label';
    frame.style.cssText = 'position:fixed;width:0;height:0;border:0;';
    document.body.append(frame);
    const cleanup = () => {
      clearTimeout(expiry);
      frame.remove();
      browserPrintFrame.current = null;
    };
    const expiry = setTimeout(cleanup, 60000);
    const doc = frame.contentDocument;
    const style = doc.createElement('style');
    style.textContent = '@page {size:4in 6in;margin:0} html,body {margin:0;width:4in;height:6in;overflow:hidden} img {display:block;width:100%;height:100%}';
    doc.head.append(style);
    const label = doc.createElement('img');
    label.alt = 'Shipping label with QR and linear barcode';
    label.onload = () => {
      frame.contentWindow.addEventListener('afterprint', cleanup, { once: true });
      try { frame.contentWindow.print(); }
      catch { cleanup(); setError('The print dialog could not open. Try again in Chrome or Edge.'); }
    };
    label.onerror = () => { cleanup(); setError('The label could not load for printing. Close the preview and try again.'); };
    label.src = `data:image/png;base64,${image.png}`;
    doc.body.append(label);
  }
  const connect = () => run(async () => {
    await local('/health'); const rows = await local('/printers'); setPrinters(rows); setPrinter(rows.includes(printer) ? printer : rows[0] || ''); sessionStorage.setItem(KEY, key);
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
    if (!window.confirm(`${prior ? 'Reprint' : 'Print'} one 4×6 label for ${parcel.trackingId} on ${printer}? Verify the loaded paper first.`)) return;
    const clientJobId = crypto.randomUUID();
    const report = await local('/jobs', { ...image, clientJobId, parcelId, trackingId: parcel.trackingId, printerName: printer, ownerId, reprint: prior, reason: reason.trim() });
    const { ownerId: _ownerId, trackingId: _trackingId, ...payload } = report;
    sessionStorage.setItem(PENDING, JSON.stringify([...pending(), { owner, report: payload }]));
    setJobs(j => [report, ...j.filter(row => row.clientJobId !== report.clientJobId)]); const left = await sync(pending());
    setNotice(`${report.message}${left ? ' Cloud history pending sync; keep this tab open.' : ' Print history synced.'}`);
  });
  return <section className="connect-cargo">
    <h3>Shipping label</h3>
    <button type="button" className="secondary-button" disabled={busy} onClick={load}>Print Label</button>
    {error && !open && <p role="alert">{error}</p>}
    {open && <div className="modal-backdrop" style={{ zIndex: 1000 }}>
      <section className="connect-command" role="dialog" aria-modal="true" aria-label="Print shipping label" style={{ maxHeight: '90vh', overflow: 'auto' }}>
        <header><h2>Print {parcel?.trackingId}</h2><button type="button" className="secondary-button" onClick={() => setOpen(false)} disabled={busy}>Close</button></header>
        <button type="button" className="primary-button" onClick={printInBrowser} disabled={busy}>Print 4 × 6 label</button>
        <p>Select your Brother printer, 4 × 6-inch portrait paper, 100% scale, and one copy.</p>
        {error && <p role="alert">{error}</p>}
        <img src={`data:image/png;base64,${image.png}`} alt="4 by 6 shipping label preview" style={{ width: 240, maxWidth: '100%', border: '1px solid #ddd' }} />
        <details>
          <summary>Direct printing and print history (optional)</summary>
          <p>For connector print history, run <code>start.cmd</code> on the Windows PC. Open the pairing-key file shown in the console privately, enter the key below, and allow local network access when prompted.</p>
          <label>Local connector pairing key<input type="password" autoComplete="off" value={key} onChange={e => { setKey(e.target.value); sessionStorage.removeItem(KEY); setConnection('Pairing required'); setPrinters([]); setPrinter(''); }} /></label>
          <button type="button" className="secondary-button" disabled={busy || !key} onClick={connect}>Connect local printer</button>
          <p role="status">Connector: {connection}</p>
          <label>Installed Windows printer<select value={printer} onChange={e => setPrinter(e.target.value)}><option value="">Select a printer</option>{printers.map(p => <option key={p}>{p}</option>)}</select></label>
          <label>Reprint reason (required after any previous job)<input maxLength={500} value={reason} onChange={e => setReason(e.target.value)} /></label>
          {notice && <p role="status">{notice}</p>}
          <button type="button" className="secondary-button" disabled={busy || !printer || !ownerId} onClick={send}>{busy ? 'Working…' : jobs.length ? 'Reprint label' : 'Print one label'}</button>
          <button type="button" className="secondary-button" disabled={busy} onClick={() => run(async () => { const pendingCount = await sync(pending()); let rows; try { rows = await local('/jobs'); } catch (e) { setNotice(pendingCount ? `${pendingCount} reports still await API sync.` : 'Saved browser reports synced. Connect to Windows for the printer’s history.'); throw e; } const unsynced = rows.filter(r => r.ownerId === ownerId && r.status !== 'PRINTING').map(r => { const {ownerId: _o, trackingId: _t, ...report} = r; return {owner, report}; }); const left = await sync([...pending(), ...unsynced]); setJobs(await request(`/label-print/parcels/${parcelId}/history`, { token })); setNotice(left ? `${left} reports remain pending. Reconnect to the D2F API.` : 'History synced.'); })}>Sync print history</button>
          <p>QUEUED means Windows accepted the job. Check the printer before reprinting an uncertain job.</p>
          {jobs.map(j => <p key={j.clientJobId}>{j.printerName} · {j.status} · {j.message}</p>)}
        </details>
      </section>
    </div>}
  </section>;
}
