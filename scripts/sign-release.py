#!/usr/bin/env python3
"""Sign both package formats and feed indexes. Private keys stay outside repo."""
import gzip,hashlib,pathlib,subprocess,os
ROOT=pathlib.Path(__file__).resolve().parents[1];DIST=ROOT/'dist'
KEYS=pathlib.Path(os.environ.get('OVERWALL_SIGNING_DIR',str(pathlib.Path.home()/'.config/overwall/openwrt-signing')))
def apk(*args):
 subprocess.run(['docker','run','--rm','--platform','linux/amd64','-v',f'{ROOT}:/work','-v',f'{KEYS}:/keys:ro','ubuntu:24.04','/work/sdk/staging_dir/host/bin/apk',*args],check=True)
def usign(*args):
 subprocess.run(['docker','run','--rm','--platform','linux/amd64','-v',f'{ROOT}:/work','-v',f'{KEYS}:/keys','ubuntu:24.04','/work/sdk/staging_dir/host/bin/usign',*args],check=True)
if not (KEYS/'overwall-usign.key').exists(): usign('-G','-s','/keys/overwall-usign.key','-p','/keys/overwall-usign.pub','-c','Overwall OpenWrt feed')
(KEYS/'overwall-usign.key').chmod(0o600)
for f in DIST.glob('*.apk'): apk('adbsign','--allow-untrusted','--reset-signatures','--sign-key','/keys/overwall-apk-ec.pem','/work/dist/'+f.name)
for release,extension in [('25.12','apk'),('24.10','ipk')]:
 feed=DIST/release;feed.mkdir(exist_ok=True)
 for f in DIST.glob('*.'+extension): (feed/f.name).write_bytes(f.read_bytes())
 if extension=='apk':
  apk('mkndx','--allow-untrusted','--sign-key','/keys/overwall-apk-ec.pem','--output','/work/dist/25.12/packages.adb',*[f'/work/dist/25.12/{f.name}' for f in feed.glob('*.apk')])
 else:
  import tarfile,io
  entries=[]
  for f in feed.glob('*.ipk'):
   with tarfile.open(f,'r:gz') as outer:
    ctrl=outer.extractfile('./control.tar.gz').read()
   with tarfile.open(fileobj=io.BytesIO(ctrl),mode='r:gz') as tar: control=tar.extractfile('./control').read().decode()
   entries.append(control+f'Filename: {f.name}\nSize: {f.stat().st_size}\nSHA256sum: {hashlib.sha256(f.read_bytes()).hexdigest()}\n')
  (feed/'Packages').write_text('\n'.join(entries))
  (feed/'Packages.gz').write_bytes(gzip.compress((feed/'Packages').read_bytes(),mtime=0))
  usign('-S','-s','/keys/overwall-usign.key','-m','/work/dist/24.10/Packages','-x','/work/dist/24.10/Packages.sig')
(DIST/'overwall-usign.pub').write_bytes((KEYS/'overwall-usign.pub').read_bytes())
(DIST/'SHA256SUMS').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+str(f.relative_to(DIST))+'\n' for f in sorted(DIST.rglob('*')) if f.is_file() and f.name!='SHA256SUMS'))
print('Signed packages and feed indexes; checksums updated')
