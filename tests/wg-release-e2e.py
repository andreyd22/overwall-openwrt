#!/usr/bin/env python3
"""Exercise slot release on the existing isolated OpenWrt/managed API lab."""
import json
from pathlib import Path
import subprocess
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
SSH=['ssh','-i',str(ROOT/'lab/id_ed25519'),'-p','12222','-o',f'UserKnownHostsFile={ROOT}/lab/known_hosts','root@127.0.0.1']
def ssh(command,data=None):
 return subprocess.run(SSH+[command],input=data,text=True,capture_output=True,check=True).stdout
def cli(action,data=None):
 if data is not None: ssh('umask 077; cat > /var/run/overwall/release-test.json',json.dumps(data))
 result=json.loads(ssh('overwall '+action+(' /var/run/overwall/release-test.json' if data is not None else '')))
 assert 'error' not in result,result
 return result
def source(): return next(s for s in cli('status')['sources'] if s['kind']=='overwall')
def refresh():
 cli('refresh',{'id':source()['id']})
 return source()
def own(): return [n['slot'] for n in refresh()['nodes'] if (n.get('ownership') or {}).get('state')=='mine']
cli('disconnect');cli('release')
# BusyBox sleep can be integer-only. Check real cancellation and stderr on-device.
started=time.monotonic()
probe=subprocess.run(SSH+["/usr/lib/overwall/background-http /bin/sleep 20 & probe=$!; sleep 1; marker=/var/run/overwall/foreground-$$; touch \"$marker\"; wait \"$probe\"; code=$?; rm -f \"$marker\"; test \"$code\" = 75"],capture_output=True,text=True,check=True)
assert not probe.stderr,probe.stderr
assert time.monotonic()-started < 4,'Foreground action failed to cancel background probe'
s=refresh(); indexes={n['slot']:i for i,n in enumerate(s['nodes']) if n['protocol']=='wireguard'}
cli('connect',{'id':s['id'],'node':indexes['1']});assert own()==['1']
cli('connect',{'id':s['id'],'node':indexes['2']});assert own()==['2']
cli('disconnect');cli('tick');assert own()==[]
assert not cli('status')['autostart']
cli('connect',{'id':s['id'],'node':indexes['1']})
# Only the isolated fixture container is paused; no production service is used.
subprocess.run(['docker','pause','overwall-openwrt-account-api'],check=True,capture_output=True)
try:
 started=time.monotonic()
 result=cli('disconnect');assert result['release_pending'] is True
 elapsed=time.monotonic()-started
 assert elapsed < 5, f'Stop waited for unavailable API: {elapsed:.2f}s'
 assert json.loads(ssh('cat /etc/overwall/wg-binding.json'))['pending'] is True
 assert not ssh('ip link show dev ow_wg 2>/dev/null || true').strip()
 if '--reboot' in sys.argv:
  old_boot = ssh('cat /proc/sys/kernel/random/boot_id').strip()
  subprocess.run(SSH+['reboot'],capture_output=True)
  time.sleep(5)
  for attempt in range(30):
   try:
    assert ssh('cat /proc/sys/kernel/random/boot_id').strip() != old_boot
    # The normal watcher may already have attempted a release; API is paused.
    assert json.loads(ssh('cat /etc/overwall/wg-binding.json'))['pending'] is True
    break
   except Exception: time.sleep(2)
  else: raise AssertionError('Router did not restore its release receipt')
finally: subprocess.run(['docker','unpause','overwall-openwrt-account-api'],check=True,capture_output=True)
# Receipts persist outside runtime state, and the normal watcher drains them.
ssh('rm -f /var/run/overwall/poll.json');cli('tick')
assert own()==[]
assert cli('status')['release_pending'] is False
print(json.dumps({'switch_releases_previous':True,'ordinary_stop_releases':True,'offline_stop_persists_receipt':True,'watcher_retries_release':True,'autostart_disabled':True,'offline_stop_seconds':round(elapsed,2)}))
