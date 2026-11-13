#!/usr/bin/env python3
"""Exercise real TCP/UDP from two clients behind the QEMU router."""
import json
import pathlib
import subprocess
import sys
import time
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))

ROOT = pathlib.Path(__file__).resolve().parents[1]
SSH = ['ssh', '-i', str(ROOT / 'lab/id_ed25519'), '-p', '12222', '-o', 'ConnectTimeout=5',
       '-o', f'UserKnownHostsFile={ROOT}/lab/known_hosts', 'root@127.0.0.1']
def ssh(command, data=None):
    return subprocess.run(SSH + [command], input=data, text=True, capture_output=True, check=True).stdout
def cli(action, data=None):
    if data is None:
        raw = ssh('overwall ' + action)
    else:
        ssh('umask 077; cat > /var/run/overwall/test-input.json', json.dumps(data))
        raw = ssh('overwall ' + action + ' /var/run/overwall/test-input.json')
    value = json.loads(raw)
    assert not value.get('error'), value
    return value
def probes(expected):
    results = []
    for index in [1, 2]:
        subprocess.run(['docker', 'cp', str(ROOT / 'tests/device-probe.py'), f'overwall-openwrt-device{index}:/tmp/overwall-probe.py'], check=True)
        result = json.loads(subprocess.check_output(['docker', 'exec', f'overwall-openwrt-device{index}', 'python', '/tmp/overwall-probe.py'], text=True))
        assert result == {'tcp': expected, 'udp': expected}, {'device': index, **result}
        results.append(result)
    return results

ssh('mkdir -p /var/run/overwall; chmod 700 /var/run/overwall')
cli('disconnect')
baseline = probes(True)
config = {'log': {'loglevel': 'none'}, 'inbounds': [{'listen': '0.0.0.0', 'port': 18443, 'protocol': 'vless', 'settings': {'clients': [{'id': '00000000-0000-4000-8000-000000000001'}], 'decryption': 'none'}}], 'outbounds': [{'protocol': 'freedom', 'settings': {'finalRules': [{'action': 'allow', 'ip': ['198.18.77.1/32']}]}}]}
(ROOT / 'lab/xray-server.json').write_text(json.dumps(config))
subprocess.run(['docker', 'exec', '-d', 'overwall-openwrt-lab', '/work/lab/xray/xray', 'run', '-config', '/work/lab/xray-server.json'], check=True)
time.sleep(1)
cli('add', {'name': 'Isolated VLESS fixture', 'kind': 'text', 'value': 'vless://00000000-0000-4000-8000-000000000001@10.0.2.2:18443?security=none&type=tcp#Lab'})
source = cli('status')['sources'][-1]
cli('connect', {'id': source['id'], 'node': 0})
vless = probes(True)
ssh('/etc/init.d/overwall-tunnel stop')
blocked = probes(False)
cli('disconnect')
restored = probes(True)
def docker(*args, data=None):
    return subprocess.run(['docker', 'exec', '-i', 'overwall-openwrt-lab', *args], input=data, text=True, capture_output=True, check=True).stdout.strip()
server_key, client_key = docker('wg', 'genkey'), docker('wg', 'genkey')
server_public = docker('wg', 'pubkey', data=server_key)
client_public = docker('wg', 'pubkey', data=client_key)
secret = ROOT / 'lab/fixture-server.key'; secret.write_text(server_key); secret.chmod(0o600)
docker('wg', 'set', 'ow-fixture', 'private-key', '/work/lab/fixture-server.key', 'listen-port', '18520', 'peer', client_public, 'allowed-ips', '10.77.0.2/32')
subprocess.run(['docker', 'exec', 'overwall-openwrt-lab', 'ip', 'addr', 'replace', '10.77.0.1/24', 'dev', 'ow-fixture'], check=True)
docker('ip', 'link', 'set', 'ow-fixture', 'up')
conf = f'[Interface]\nPrivateKey = {client_key}\nAddress = 10.77.0.2/32\nDNS = 9.9.9.9\n[Peer]\nPublicKey = {server_public}\nEndpoint = 10.0.2.2:18520\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25'
cli('add', {'name': 'Isolated WireGuard fixture', 'kind': 'wireguard', 'value': conf})
source = cli('status')['sources'][-1]
cli('connect', {'id': source['id'], 'node': 0})
wireguard = probes(True)
ssh('ifdown ow_wg')
wg_blocked = probes(False)
cli('disconnect')
probes(True)
report = {'baseline': baseline, 'vless': vless, 'vless_failure_closed': blocked, 'explicit_disconnect': restored, 'wireguard': wireguard, 'wireguard_failure_closed': wg_blocked}
(ROOT / 'lab/e2e-results.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
