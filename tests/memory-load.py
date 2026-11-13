#!/usr/bin/env python3
"""Measure guest memory and real forwarded load from two isolated LAN clients."""
import concurrent.futures,json,pathlib,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
SSH=['ssh','-i',str(ROOT/'lab/id_ed25519'),'-p','12222','-o',f'UserKnownHostsFile={ROOT}/lab/known_hosts','root@127.0.0.1']
def ssh(cmd): return subprocess.check_output(SSH+[cmd],text=True)
def cli(cmd,data=None):
 if data is not None:
  subprocess.run(SSH+['umask 077; cat > /var/run/overwall/load-input.json'],input=json.dumps(data),text=True,check=True)
  cmd+=' /var/run/overwall/load-input.json'
 value=json.loads(ssh('overwall '+cmd)); assert not value.get('error'),value
 return value
SAMPLE='''awk '/MemTotal:|MemAvailable:|Slab:|SUnreclaim:/{print $1,$2}' /proc/meminfo; for pid in $(pidof xray ucode rpcd uhttpd curl); do p=/proc/$pid; n=$(cat "$p/comm" 2>/dev/null); case "$n" in xray|ucode|rpcd|uhttpd|curl) printf 'PROC %s ' "$n"; awk '/VmRSS:/{print $2}' "$p/status";; esac; done'''
def sample():
 fields={}; procs={}
 for line in ssh(SAMPLE).splitlines():
  cols=line.split()
  if cols[0]=='PROC':
   if len(cols)==3: procs[cols[1]]=procs.get(cols[1],0)+int(cols[2])
  else: fields[cols[0].rstrip(':')]=int(cols[1])
 fields['used_available_kib']=fields['MemTotal']-fields['MemAvailable'];fields['process_rss_kib']=procs
 return fields
def summarize(samples):
 return {'samples':len(samples),'total_kib':samples[0]['MemTotal'],'peak_used_kib':max(x['used_available_kib'] for x in samples),'min_available_kib':min(x['MemAvailable'] for x in samples),'peak_process_rss_kib':{n:max(x['process_rss_kib'].get(n,0) for x in samples) for n in ['xray','ucode','rpcd','uhttpd','curl']},'raw':samples}
status=cli('status'); custom=next(s for s in status['sources'] if s['kind']=='text'); wg=next(s for s in status['sources'] if s['kind']=='overwall')
for n in [1,2]: subprocess.run(['docker','cp',str(ROOT/'tests/load-device.py'),f'overwall-openwrt-device{n}:/tmp/load-device.py'],check=True)
ssh('/etc/init.d/overwall stop'); cli('disconnect'); baseline=summarize([sample() for _ in range(5)])
report={'environment':'OpenWrt 25.12.6 x86_64, QEMU TCG, health polling paused for isolated fixture, two LAN clients, 16 TCP streams, 60 seconds per protocol','baseline':baseline}
for protocol,source,node in [('vless',wg,0),('wireguard',wg,3)]:
 cli('connect',{'id':source['id'],'node':node})
 idle=summarize([sample() for _ in range(5)])
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  futures=[pool.submit(subprocess.check_output,['docker','exec',f'overwall-openwrt-device{n}','python','/tmp/load-device.py'],text=True) for n in [1,2]]
  samples=[]
  while not all(f.done() for f in futures): samples.append(sample());time.sleep(2)
  clients=[json.loads(f.result()) for f in futures]
 assert all(c['bytes']>0 for c in clients),clients
 report[protocol]={'idle':idle,'load':summarize(samples),'clients':clients,'aggregate_mbps':sum(c['bytes'] for c in clients)*8/60/1e6}
 print(protocol,json.dumps({k:v for k,v in report[protocol].items() if k not in ['idle','load']}),flush=True)
cli('disconnect'); ssh('/etc/init.d/overwall start')
(ROOT/'lab/memory-load-results.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:({j:v for j,v in val.items() if j!='raw'} if k=='baseline' else {j:({a:b for a,b in v.items() if a!='raw'} if j in ['idle','load'] else v) for j,v in val.items()}) for k,val in report.items() if k!='environment'},indent=2))
