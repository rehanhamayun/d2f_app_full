import base64
import hashlib
import http.client
import json
from pathlib import Path
import struct
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from connector import PrintStore, make_handler

class ConnectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.sent = []
        self.store = PrintStore(self.temp.name, lambda: ['Brother'], lambda *args: self.sent.append(args))
        data = b'\x89PNG\r\n\x1a\n' + b'\0'*8 + struct.pack('>II', 1200, 1800) + b'\0'*20
        self.job = dict(clientJobId='test-1', parcelId='p1', trackingId='D2F1', ownerId='api:user1', printerName='Brother', png=base64.b64encode(data).decode(), labelHash=hashlib.sha256(data).hexdigest())

    def tearDown(self): self.temp.cleanup()

    def test_idempotent_and_explicit_reprints(self):
        self.assertEqual(self.store.submit(self.job)['status'], 'QUEUED')
        self.assertEqual(self.store.submit(self.job)['status'], 'QUEUED')
        self.assertEqual(len(self.sent), 1)
        with self.assertRaises(ValueError): self.store.submit(dict(self.job, clientJobId='test-2'))
        with self.assertRaises(ValueError): self.store.submit(dict(self.job, clientJobId='test-2', reprint=True))
        self.store.submit(dict(self.job, clientJobId='test-2', reprint=True, reason='Damaged label'))
        self.assertEqual(len(self.sent), 2)
        self.assertFalse(list(Path(self.temp.name).glob('label-*.png')))

    def test_interrupted_or_failed_job_is_never_retried(self):
        def fail(*_): raise RuntimeError('spooler failure')
        self.store.send = fail
        self.assertEqual(self.store.submit(self.job)['status'], 'UNKNOWN')
        self.store.send = lambda *args: self.sent.append(args)
        self.assertEqual(self.store.submit(self.job)['status'], 'UNKNOWN')
        self.assertEqual(len(self.sent), 0)

    def test_validation(self):
        for change in [dict(clientJobId='../bad'),dict(printerName='Not installed'),dict(labelHash='b'*64),dict(png='invalid'),dict(ownerId='')]:
            with self.assertRaises(ValueError): self.store.submit(dict(self.job, **change))
        self.assertEqual(len(self.sent), 0)

    def test_origin_host_and_pairing_key(self):
        server = ThreadingHTTPServer(('127.0.0.1',0),make_handler(self.store))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        def get(origin='https://d2f-admin-dashboard.pages.dev',key=None,host='127.0.0.1:18441'):
            c=http.client.HTTPConnection('127.0.0.1',server.server_port)
            c.request('GET','/health',headers={'Host':host,'Origin':origin,'Authorization':'Bearer '+(key or self.store.token)})
            r=c.getresponse();status=r.status;r.read();c.close();return status
        try:
            self.assertEqual(get(),200)
            self.assertEqual(get(origin='https://evil.example'),403)
            self.assertEqual(get(key='wrong'),401)
            self.assertEqual(get(host='evil.example:18441'),403)
        finally: server.shutdown();server.server_close()

if __name__ == '__main__': unittest.main()
