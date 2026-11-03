#!/usr/bin/env python3
"""D2F local Windows print bridge. No cloud credentials or public listener."""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import struct
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ORIGINS = {'https://d2f-admin-dashboard.pages.dev'}
MAX_BODY = 8_000_000

class PrintStore:
    def __init__(self, folder, printers, send):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True)
        token_file = self.folder / 'pairing-key.txt'
        if not token_file.exists():
            token_file.write_text(secrets.token_urlsafe(32))
        self.token = token_file.read_text().strip()
        self.printers, self.send = printers, send
        self.lock = threading.Lock()

    def history(self):
        rows = []
        for path in self.folder.glob('job-*.json'):
            row = json.loads(path.read_text())
            if row['status'] == 'PRINTING':
                row.update(status='UNKNOWN', message='Connector interrupted. Check the physical label before reprinting.')
            rows.append(row)
        return sorted(rows, key=lambda row: row['deviceTimeMs'], reverse=True)

    def submit(self, body):
        job_id = body.get('clientJobId', '')
        if not isinstance(job_id, str) or not 1 <= len(job_id) <= 160 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in job_id):
            raise ValueError('Invalid print job ID.')
        printer = body.get('printerName')
        if printer not in self.printers():
            raise ValueError('Choose an installed Windows printer queue.')
        try:
            data = base64.b64decode(body['png'], validate=True)
        except (KeyError, ValueError, TypeError):
            raise ValueError('Invalid shipping label image.')
        if not 33 <= len(data) <= 5_500_000 or data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (1200, 1800):
            raise ValueError('The label must be a 1200 × 1800 PNG (4×6 at 300 dpi).')
        digest = hashlib.sha256(data).hexdigest()
        if body.get('labelHash') != digest:
            raise ValueError('Label checksum does not match.')
        reason = body.get('reason', '')
        if not isinstance(reason, str) or len(reason) > 500 or (body.get('reprint') is True and not reason.strip()):
            raise ValueError('Provide a reason for an explicit reprint.')
        for key in ('parcelId', 'trackingId', 'ownerId'):
            if not isinstance(body.get(key), str) or not 1 <= len(body[key]) <= 200:
                raise ValueError('Missing parcel or staff identity.')
        with self.lock:
            path = self.folder / ('job-' + job_id + '.json')
            rows = self.history()
            for old in rows:
                if old['clientJobId'] == job_id:
                    if any(old[k] != body[k] for k in ('parcelId', 'printerName', 'labelHash', 'ownerId')):
                        raise ValueError('Job ID already used for another label.')
                    return old
            if body.get('reprint') is not True and any(r['labelHash'] == digest and r['printerName'] == printer and time.time()*1000-r['deviceTimeMs'] < 120000 for r in rows):
                raise ValueError('This label was recently sent. Check the physical output and use explicit Reprint if necessary.')
            row = {k: body[k] for k in ('clientJobId', 'parcelId', 'trackingId', 'printerName', 'ownerId')}
            row.update(labelHash=digest, reason=reason.strip(), pages=1, source='WINDOWS_LOCAL_CONNECTOR', status='PRINTING', deviceTimeMs=int(time.time()*1000))
            self._save(path, row)
            image = self.folder / ('label-' + job_id + '.png')
            image.write_bytes(data)
            try:
                self.send(image, printer, job_id)
                row.update(status='QUEUED', message='Windows accepted the print job. Verify the physical label at the printer.')
            except Exception:
                row.update(status='UNKNOWN', message='Windows printing did not complete normally. Check the printer queue and physical output before explicitly reprinting.')
            finally:
                self._save(path, row)
                image.unlink(missing_ok=True)
            return row

    @staticmethod
    def _save(path, row):
        temporary = path.with_suffix('.tmp')
        with temporary.open('w') as handle:
            json.dump(row, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)


def windows_printers():
    raw = subprocess.check_output(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', '@(Get-Printer | Select-Object -ExpandProperty Name) | ConvertTo-Json -Compress'], text=True, timeout=20)
    result = json.loads(raw or '[]')
    return [result] if isinstance(result, str) else result


def windows_send(image, printer, job_id):
    params = image.with_suffix('.input.json')
    params.write_text(json.dumps({'image': str(image.resolve()), 'printer': printer, 'job': job_id}))
    try:
        subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(Path(__file__).with_name('print-label.ps1')), '-InputPath', str(params.resolve())], check=True, timeout=90, capture_output=True)
    finally:
        params.unlink(missing_ok=True)


def make_handler(store, origins=ORIGINS):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # pairing keys and labels must never appear in HTTP logs

        def reply(self, code, data):
            self.send_response(code)
            origin = self.headers.get('Origin')
            if origin in origins:
                self.send_header('Access-Control-Allow-Origin', origin)
                self.send_header('Vary', 'Origin')
                self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
                self.send_header('Access-Control-Allow-Private-Network', 'true')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Type', 'application/json')
            payload = b'' if code == 204 else json.dumps(data).encode()
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def allowed(self):
            # Also reject DNS rebinding and browser requests from unknown sites.
            if self.headers.get('Host') not in ('127.0.0.1:18441', 'localhost:18441') or self.headers.get('Origin') not in origins:
                self.reply(403, {'error': 'Open the approved D2F dashboard to use this connector.'})
                return False
            if not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + store.token):
                self.reply(401, {'error': 'Enter the pairing key shown by the local D2F connector.'})
                return False
            return True

        def do_OPTIONS(self):
            self.reply(204 if self.headers.get('Origin') in origins else 403, {})

        def do_GET(self):
            if not self.allowed(): return
            try:
                if self.path == '/health': self.reply(200, {'ready': True, 'version': '1.1.8'})
                elif self.path == '/printers': self.reply(200, store.printers())
                elif self.path == '/jobs': self.reply(200, store.history())
                else: self.reply(404, {'error': 'Unknown connector endpoint.'})
            except Exception:
                self.reply(503, {'error': 'Windows printer queues are unavailable. Check the printer driver and spooler.'})

        def do_POST(self):
            if not self.allowed(): return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if self.path != '/jobs' or not 0 < length <= MAX_BODY or self.headers.get('Content-Type') != 'application/json':
                    raise ValueError('Invalid print request.')
                self.reply(200, store.submit(json.loads(self.rfile.read(length))))
            except (ValueError, TypeError, KeyError) as error:
                self.reply(400, {'error': str(error)})
            except Exception:
                self.reply(500, {'error': 'Could not record the print result. Check physical output before reprinting.'})
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dev-origin', choices=['http://localhost:5173', 'http://127.0.0.1:5173'])
    args = parser.parse_args()
    if os.name != 'nt': raise SystemExit('Run this connector on Windows with the Brother printer driver installed.')
    folder = Path(os.environ['LOCALAPPDATA']) / 'D2F' / 'LabelPrint'
    store = PrintStore(folder, windows_printers, windows_send)
    origins = ORIGINS | ({args.dev_origin} if args.dev_origin else set())
    print('D2F local printing: http://127.0.0.1:18441')
    print('Pairing key (enter only in your D2F dashboard):', store.token)
    print('Keep this window open. Press Ctrl+C to stop. No automatic print retries.')
    ThreadingHTTPServer(('127.0.0.1', 18441), make_handler(store, origins)).serve_forever()
