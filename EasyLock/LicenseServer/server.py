"""Local reference license service. Deploy behind TLS, authentication-aware rate limits and backups."""
from contextlib import contextmanager
import argparse
import base64
import hashlib
import json
import secrets
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

class Denied(Exception):
    def __init__(self, status=403): self.status = status

class Service:
    def __init__(self, database, key):
        self.database, self.key = str(database), key
        with self.connect() as db:
            db.executescript('''
              CREATE TABLE IF NOT EXISTS licenses (id TEXT PRIMARY KEY, digest TEXT UNIQUE NOT NULL, enabled INTEGER NOT NULL);
              CREATE TABLE IF NOT EXISTS devices (license TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, seen REAL NOT NULL, PRIMARY KEY(license,id));
              CREATE TABLE IF NOT EXISTS nonces (device TEXT NOT NULL, nonce TEXT NOT NULL, at REAL NOT NULL, PRIMARY KEY(device,nonce));
            ''')
    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.database, timeout=15)
        try:
            db.execute('PRAGMA foreign_keys=ON')
            with db: yield db
        finally: db.close()
    def issue(self):
        code = 'EL-' + secrets.token_urlsafe(32)
        with self.connect() as db:
            db.execute('INSERT INTO licenses VALUES (?,?,1)', (secrets.token_hex(16), hashlib.sha256(code.encode()).hexdigest()))
        return code
    def process(self, envelope, now=None):
        now = time.time() if now is None else now
        try:
            payload = base64.b64decode(envelope['payload'], validate=True)
            signature = base64.b64decode(envelope['signature'], validate=True)
            if len(payload) > 16384: raise Denied(400)
            request = json.loads(payload)
            public = base64.b64decode(request['publicKey'], validate=True)
            Ed25519PublicKey.from_public_bytes(public).verify(signature, payload)
            device = hashlib.sha256(public).hexdigest()
            stamp = request['timestamp']
            if not isinstance(stamp, (int, float)) or not abs(now - stamp) <= 300: raise Denied(403)
            action, nonce, code = request['action'], request['nonce'], request['license']
            name = request.get('deviceName', 'Mac')
            if action not in ('activate', 'inspect', 'refresh', 'deactivate'): raise Denied(400)
            if not isinstance(nonce, str) or not 16 <= len(nonce) <= 128: raise Denied(400)
            if not isinstance(code, str) or not 16 <= len(code) <= 256: raise Denied(400)
            if not isinstance(name, str) or not 1 <= len(name) <= 100 or any(ord(c) < 32 for c in name): raise Denied(400)
        except Denied: raise
        except Exception: raise Denied(400) from None
        with self.connect() as db:
            # The limit check and insertion share one write transaction, including concurrent clients.
            db.execute('BEGIN IMMEDIATE')
            license = db.execute('SELECT id FROM licenses WHERE digest=? AND enabled=1', (hashlib.sha256(code.encode()).hexdigest(),)).fetchone()
            if not license: raise Denied()
            license = license[0]
            db.execute('DELETE FROM nonces WHERE at < ?', (now - 600,))
            try: db.execute('INSERT INTO nonces VALUES (?,?,?)', (device, nonce, now))
            except sqlite3.IntegrityError: raise Denied()
            current = db.execute('SELECT 1 FROM devices WHERE license=? AND id=?', (license, device)).fetchone()
            if action == 'activate':
                count = db.execute('SELECT COUNT(*) FROM devices WHERE license=?', (license,)).fetchone()[0]
                if not current and count >= 3: raise Denied(409)
                db.execute('INSERT INTO devices VALUES (?,?,?,?) ON CONFLICT(license,id) DO UPDATE SET name=excluded.name, seen=excluded.seen', (license, device, name, now))
            elif action == 'inspect':
                pass  # Possession of a license authorizes device management, even on a fourth Mac.
            elif action == 'refresh':
                if not current: raise Denied()
                db.execute('UPDATE devices SET seen=? WHERE license=? AND id=?', (now, license, device))
            else:
                target = request.get('targetDeviceID', device)
                if not isinstance(target, str) or len(target) != 64: raise Denied(400)
                db.execute('DELETE FROM devices WHERE license=? AND id=?', (license, target))
            devices = [dict(id=row[0], name=row[1], lastSeen=row[2]) for row in db.execute('SELECT id,name,seen FROM devices WHERE license=? ORDER BY id', (license,))]
            response = dict(licenseID=license, deviceID=device, seatLimit=3, issuedAt=now, expiresAt=now + 7*86400,
                            status='active' if any(d['id'] == device for d in devices) else 'inactive', devices=devices)
            raw = json.dumps(response, separators=(',', ':'), ensure_ascii=False).encode()
            result = dict(payload=base64.b64encode(raw).decode(), signature=base64.b64encode(self.key.sign(raw)).decode())
        return result

class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)
    def do_POST(self):
        try:
            if self.path != '/v1/license': raise Denied(404)
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 32768: raise Denied(413)
            result = self.server.service.process(json.loads(self.rfile.read(length)))
            self.respond(200, result)
        except Denied as error: self.respond(error.status, {'error': 'request_denied'})
        except (ValueError, KeyError): self.respond(400, {'error': 'invalid_request'})
        except Exception: self.respond(503, {'error': 'temporarily_unavailable'})
    def respond(self, status, value):
        raw = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers(); self.wfile.write(raw)
    def log_message(self, *args): pass  # Never log license keys, payloads or device names.

if __name__ == '__main__':
    import os
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['init', 'issue', 'serve'])
    parser.add_argument('--directory', default='./license-data')
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    root = Path(args.directory); root.mkdir(parents=True, exist_ok=True)
    path = root/'signing.key'
    if args.command == 'init':
        key = Ed25519PrivateKey.generate()
        with path.open('xb') as file: file.write(key.private_bytes_raw())
        print('Public verification key:', base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode())
    else:
        service = Service(root/'licenses.sqlite3', Ed25519PrivateKey.from_private_bytes(path.read_bytes()))
        if args.command == 'issue': print(service.issue())
        else:
            server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
            server.service = service
            print('Local service listening; production TLS/rate limiting is required.')
            server.serve_forever()
