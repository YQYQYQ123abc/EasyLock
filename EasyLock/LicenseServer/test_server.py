import base64
import concurrent.futures
import json
import secrets
import tempfile
import time
import unittest
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from server import Service, Denied

class LicenseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.service = Service(Path(self.temp.name)/'test.db', Ed25519PrivateKey.generate())
        self.code = self.service.issue()
    def tearDown(self): self.temp.cleanup()
    def request(self, key, action='activate', **extras):
        fields = dict(action=action, license=self.code, publicKey=base64.b64encode(key.public_key().public_bytes_raw()).decode(), timestamp=time.time(), nonce=secrets.token_hex(16), deviceName='测试 Mac')
        fields.update(extras)
        raw = json.dumps(fields).encode()
        return dict(payload=base64.b64encode(raw).decode(), signature=base64.b64encode(key.sign(raw)).decode())
    def read(self, result):
        raw = base64.b64decode(result['payload'])
        self.service.key.public_key().verify(base64.b64decode(result['signature']), raw)
        return json.loads(raw)
    def test_concurrent_seat_limit(self):
        def activate(_):
            try: self.service.process(self.request(Ed25519PrivateKey.generate())); return True
            except Denied as error: self.assertEqual(error.status, 409); return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            self.assertEqual(sum(pool.map(activate, range(8))), 3)
    def test_refresh_replay_tamper_and_release(self):
        key = Ed25519PrivateKey.generate()
        request = self.request(key)
        first = self.read(self.service.process(request))
        with self.assertRaises(Denied): self.service.process(request)
        self.assertEqual(len(self.read(self.service.process(self.request(key)))['devices']), 1)
        self.assertEqual(self.read(self.service.process(self.request(key, 'refresh')))['status'], 'active')
        request = self.request(key); request['signature'] = base64.b64encode(bytes(64)).decode()
        with self.assertRaises(Denied): self.service.process(request)
        with self.assertRaises(Denied): self.service.process(self.request(key, timestamp=time.time()-1000))
        self.assertEqual(self.read(self.service.process(self.request(key, 'deactivate', targetDeviceID=first['deviceID'])))['status'], 'inactive')
        with self.assertRaises(Denied): self.service.process(self.request(key, 'refresh'))
        self.assertEqual(self.read(self.service.process(self.request(key)))['status'], 'active')
    def test_fourth_device_can_manage_but_cannot_exceed_limit(self):
        keys = [Ed25519PrivateKey.generate() for _ in range(4)]
        first = self.read(self.service.process(self.request(keys[0])))
        for key in keys[1:3]: self.service.process(self.request(key))
        with self.assertRaises(Denied): self.service.process(self.request(keys[3]))
        inspection = self.read(self.service.process(self.request(keys[3], 'inspect')))
        self.assertEqual(inspection['status'], 'inactive')
        self.assertEqual(len(inspection['devices']), 3)
        self.service.process(self.request(keys[3], 'deactivate', targetDeviceID=first['deviceID']))
        self.assertEqual(self.read(self.service.process(self.request(keys[3])))['status'], 'active')
        with self.assertRaises(Denied): self.service.process(self.request(keys[0], 'refresh'))
    def test_other_license_and_remote_unbind(self):
        one, two = Ed25519PrivateKey.generate(), Ed25519PrivateKey.generate()
        a = self.read(self.service.process(self.request(one)))
        b = self.read(self.service.process(self.request(two)))
        self.assertEqual(len(b['devices']), 2)
        result = self.read(self.service.process(self.request(one, 'deactivate', targetDeviceID=b['deviceID'])))
        self.assertEqual(len(result['devices']), 1)
        with self.assertRaises(Denied): self.service.process(self.request(two, 'refresh'))
        with self.assertRaises(Denied): self.service.process(self.request(one, license=self.service.issue(), action='refresh'))

if __name__ == '__main__': unittest.main()
