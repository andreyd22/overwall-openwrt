#!/usr/bin/env python3
"""Pair the real router client against isolated TLS + real backend/Valkey."""
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SSH = ['ssh', '-i', str(ROOT / 'lab/id_ed25519'), '-p', '12222', '-o', 'ConnectTimeout=5',
       '-o', f'UserKnownHostsFile={ROOT}/lab/known_hosts', 'root@127.0.0.1']
def ssh(command, data=None):
    return subprocess.run(SSH + [command], input=data, text=True, capture_output=True, check=True).stdout
def cli(action, data=None):
    if data is None:
        return json.loads(ssh('overwall ' + action))
    ssh('umask 077; cat > /var/run/overwall/test-input.json', json.dumps(data))
    return json.loads(ssh('overwall ' + action + ' /var/run/overwall/test-input.json'))
def control(state, wg=True):
    subprocess.run(['docker', 'exec', 'overwall-openwrt-lab', 'curl', '-fsS', '-H', 'Content-Type: application/json', '-d', json.dumps({'state': state, 'wireguard': wg}), 'http://127.0.0.1:19000/access'], check=True, capture_output=True)
def tick():
    ssh('rm -f /var/run/overwall/poll.json')
    cli('tick')
def client(index, code):
    subprocess.run(['docker', 'exec', f'overwall-openwrt-device{index}', 'python', '/tmp/overwall-probe.py', 'route'], check=True, capture_output=True)
    return subprocess.run(['docker', 'exec', f'overwall-openwrt-device{index}', 'python', '-c', code], text=True, capture_output=True, check=True).stdout.strip()

cli('disconnect'); control('active')
# This container is dedicated to this test and is never a production connection.
subprocess.run(['docker', 'exec', 'overwall-openwrt-account-valkey', 'valkey-cli', '-p', '16379', 'FLUSHDB'], check=True, capture_output=True)
pair = cli('pair')
assert pair['qr_svg'].startswith('<?xml')
assert not any(key in pair for key in ['device_secret', 'installation_id', 'access_token', 'refresh_token'])
assert cli('pair_poll') == {'pending': True}
device_id = pair['verification_uri'].split('id=', 1)[1]
approved = subprocess.run(['docker', 'exec', 'overwall-openwrt-lab', 'curl', '-fsS', '--cacert', '/work/lab/tls/fixture.crt', '--resolve', 'overwall.online:443:198.18.77.1', '-H', 'Content-Type: application/json', '-d', json.dumps({'id': device_id, 'csrf_token': 'fixture-csrf'}), 'https://overwall.online/client/tv/activate'], check=True, capture_output=True, text=True)
assert 'Устройство подключено' in approved.stdout
time.sleep(5)
assert cli('pair_poll')['success'] is True
source = next(s for s in cli('status')['sources'] if s['kind'] == 'overwall')
cli('connect', {'id': source['id'], 'node': 0})
control('traffic_exhausted', True); tick()
status = cli('status')
assert status['portal']['reason'] == 'traffic_exhausted'
assert status['state'] == 'restricted'
for index in [1, 2]:
    code = """import http.client,json
c=http.client.HTTPConnection('198.18.77.1',80,timeout=8);c.request('GET','/',headers={'Host':'example.com'});r=c.getresponse();body=r.read().decode();assert r.status==200 and 'Overwall VPN' in body and 'https://overwall.online/' in body
c=http.client.HTTPConnection('172.30.77.1',2050,timeout=8);c.request('GET','/reason.json');r=c.getresponse();assert json.loads(r.read())['reason']=='traffic_exhausted';print('portal ok')"""
    assert client(index, code) == 'portal ok'
control('active'); tick()
assert cli('status')['portal'] is None
assert cli('status')['state'] == 'connected'
cli('disconnect')
report = {'tls_pairing': True, 'qr_without_device_secret': True, 'pending_before_approval': True, 'quota_portal_both_clients': True, 'automatic_recovery': True}
(ROOT / 'lab/account-e2e-results.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
