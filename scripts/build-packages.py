#!/usr/bin/env python3
"""Package the architecture-independent client using official SDK apk-tools.

The SDK must be unpacked at ./sdk and the amd64 Docker builder must be running.
No downloaded binary or user configuration is embedded in these packages.
"""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.1.0'
DIST = ROOT / 'dist'
DIST.mkdir(exist_ok=True)
CLIENT_DEPS = 'ucode ucode-mod-fs ucode-mod-uci ucode-mod-ubus curl ca-bundle resolveip flock coreutils-timeout ip-full nftables-json kmod-nft-tproxy kmod-wireguard wireguard-tools xray-core uhttpd qrencode'
PACKAGES = {'overwall-client': CLIENT_DEPS, 'luci-app-overwall': 'overwall-client luci-base rpcd-mod-ucode'}
POST = '''#!/bin/sh
set -eu
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
umask 077
mkdir -p /etc/overwall /var/run/overwall
chmod 700 /etc/overwall /var/run/overwall
if [ -f /etc/uci-defaults/90-overwall ]; then
 sh /etc/uci-defaults/90-overwall
 rm /etc/uci-defaults/90-overwall
fi
/etc/init.d/overwall enable
/etc/init.d/overwall start
exit 0
'''
PRE = '''#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
/usr/bin/overwall disconnect >/dev/null 2>&1 || exit 1
/etc/init.d/overwall stop
/etc/init.d/overwall disable
uci -q delete firewall.ow_boot_guard
uci commit firewall
exit 0
'''
LUCI_POST = '''#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
exit 0
'''

def archive(files):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w', format=tarfile.GNU_FORMAT) as tar:
        parents = set()
        for name, _, _ in files:
            parents.update(str(p) for p in Path(name).parents if str(p) != '.')
        for parent in sorted(parents, key=lambda p: (p.count('/'), p)):
            info = tarfile.TarInfo('./' + parent + '/')
            info.type = tarfile.DIRTYPE; info.mode = 0o755
            info.uid = info.gid = 0; info.mtime = 1794528000
            tar.addfile(info)
        for name, content, mode in files:
            info = tarfile.TarInfo('./' + name)
            info.mode = mode; info.uid = info.gid = 0; info.mtime = 1794528000
            info.size = len(content)
            tar.addfile(info, io.BytesIO(content))
    return gzip.compress(data.getvalue(), mtime=0)

for name, depends in PACKAGES.items():
    stage = ROOT / 'lab/package-stage' / name
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    base = ROOT / 'packages' / name
    for directory, prefix in [('files', ''), ('root', ''), ('htdocs', 'www')]:
        source = base / directory
        if not source.exists():
            continue
        for file in source.rglob('*'):
            if not file.is_file() or file.name.startswith('._'):
                continue
            relative = str(file.relative_to(source)).replace('usr/share/overwall/', 'usr/share/ucode/overwall/', 1)
            target = stage / prefix / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(file.read_bytes())
            target.chmod(0o755 if relative.startswith(('usr/bin/', 'usr/lib/overwall/', 'etc/init.d/', 'etc/uci-defaults/')) else 0o644)
    post = POST if name == 'overwall-client' else LUCI_POST
    pre = PRE if name == 'overwall-client' else '#!/bin/sh\nexit 0\n'
    scripts = ROOT / 'lab/package-scripts' / name
    scripts.mkdir(parents=True, exist_ok=True)
    for script, body in [('postinst', post), ('prerm', pre)]:
        (scripts / script).write_text(body); (scripts / script).chmod(0o755)
    control = f'Package: {name}\nVersion: {VERSION}-1\nArchitecture: all\nMaintainer: Overwall\nSection: net\nPriority: optional\nLicense: Apache-2.0\nDepends: {", ".join(depends.split())}\nDescription: Overwall VPN for LuCI\n'
    controls = archive([('control', control.encode(), 0o644), ('postinst', post.encode(), 0o755), ('prerm', pre.encode(), 0o755)])
    data = archive([(str(f.relative_to(stage)), f.read_bytes(), f.stat().st_mode & 0o777) for f in sorted(stage.rglob('*')) if f.is_file()])
    (DIST / f'{name}_{VERSION}-1_all.ipk').write_bytes(archive([('debian-binary', b'2.0\n', 0o644), ('data.tar.gz', data, 0o644), ('control.tar.gz', controls, 0o644)]))
    arguments = ['docker', 'exec', 'overwall-openwrt-builder', '/work/sdk/staging_dir/host/bin/apk', 'mkpkg']
    for key, value in [('name', name), ('version', VERSION + '-r1'), ('arch', 'noarch'), ('license', 'Apache-2.0'), ('description', 'Overwall VPN for LuCI'), ('url', 'https://overwall.online'), ('depends', depends)]:
        arguments += ['--info', f'{key}:{value}']
    arguments += ['--files', '/work/' + str(stage.relative_to(ROOT)), '--output', f'/work/dist/{name}-{VERSION}-r1.apk']
    arguments += ['--script', 'post-install:/work/' + str((scripts / 'postinst').relative_to(ROOT)), '--script', 'post-upgrade:/work/' + str((scripts / 'postinst').relative_to(ROOT)), '--script', 'pre-deinstall:/work/' + str((scripts / 'prerm').relative_to(ROOT))]
    subprocess.run(arguments, check=True)
checksums = []
for package in sorted(DIST.glob('*')):
    if package.suffix in ['.ipk', '.apk']:
        checksums.append(hashlib.sha256(package.read_bytes()).hexdigest() + '  ' + package.name)
(DIST / 'SHA256SUMS').write_text('\n'.join(checksums) + '\n')
print('Built ' + str(len(checksums)) + ' packages; signatures are a separate release step.')
