#!/usr/bin/env python3
"""Check the actual LuCI/ubus access boundary and asynchronous job transport."""
import json
from pathlib import Path
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SSH = ['ssh', '-i', str(ROOT / 'lab/id_ed25519'), '-p', '12222', '-o', 'ConnectTimeout=5',
       '-o', f'UserKnownHostsFile={ROOT}/lab/known_hosts', 'root@127.0.0.1']
def ubus(object_name, method, body):
    raw = json.dumps(body).replace("'", "'\\''")
    return json.loads(subprocess.check_output(SSH + [f"ubus call {object_name} {method} '{raw}'"], text=True) or "{}")
def rpc(session, method, body=None):
    payload = {'jsonrpc': '2.0', 'id': 1, 'method': 'call', 'params': [session, 'luci.overwall', method, body or {}]}
    request = urllib.request.Request('http://127.0.0.1:18080/ubus/', json.dumps(payload).encode(), {'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(request, timeout=10))
def denied(result):
    return bool(result.get('error')) or result.get('result', [0])[0] != 0
def success(result):
    assert result.get('result', [99])[0] == 0, result
    return result['result'][1]

anonymous = rpc('0' * 32, 'status')
assert denied(anonymous)
readonly = ubus('session', 'create', {'timeout': 120})['ubus_rpc_session']
ubus('session', 'grant', {'ubus_rpc_session': readonly, 'scope': 'ubus', 'objects': [['luci.overwall', 'status']]})
status = success(rpc(readonly, 'status'))
serialized = json.dumps(status)
assert all(secret not in serialized for secret in ['vless://', 'PrivateKey', 'private_key', 'refresh_token', 'installation_id', 'device_secret'])
assert denied(rpc(readonly, 'command', {'action': 'disconnect', 'data': '{}'}))
assert denied(rpc(readonly, 'job', {'id': 'A' * 43}))
admin = ubus('session', 'login', {'username': 'root', 'password': ''})['ubus_rpc_session']
payload = {'name': 'RPC fixture', 'kind': 'text', 'value': 'vless://00000000-0000-4000-8000-000000000001@192.0.2.1:443?security=tls#RPC'}
started = time.monotonic()
job = success(rpc(admin, 'command', {'action': 'add', 'data': json.dumps(payload)}))
assert time.monotonic() - started < 2, 'RPC must not block on VPN/network work'
assert 'job_id' in job
for _ in range(30):
    result = success(rpc(admin, 'job', {'id': job['job_id']}))
    if result['done']:
        assert result['result'] == {'success': True}, result
        break
    time.sleep(.2)
else:
    raise AssertionError('Job did not finish')
status = success(rpc(admin, 'status'))
assert any(source['name'] == 'RPC fixture' for source in status['sources'])
ubus('session', 'destroy', {'ubus_rpc_session': readonly})
ubus('session', 'destroy', {'ubus_rpc_session': admin})
report = {'anonymous_denied': True, 'readonly_status_only': True, 'no_credentials_in_status': True, 'queued_admin_import': True}
(ROOT / 'lab/rpc-e2e-results.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
