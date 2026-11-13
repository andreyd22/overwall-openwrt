#!/usr/bin/env python3
"""Install a development overlay into the isolated lab (not a release package)."""
import io
import pathlib
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SSH = ['ssh', '-i', str(ROOT / 'lab/id_ed25519'), '-p', '12222', '-o', 'ConnectTimeout=5',
       '-o', 'StrictHostKeyChecking=accept-new', '-o', f'UserKnownHostsFile={ROOT}/lab/known_hosts', 'root@127.0.0.1']
data = io.BytesIO()
with tarfile.open(fileobj=data, mode='w') as archive:
    for package in ['overwall-client', 'luci-app-overwall']:
        base = ROOT / 'packages' / package
        for directory, prefix in [('files', ''), ('root', ''), ('htdocs', 'www')]:
            source = base / directory
            if not source.exists():
                continue
            for path in source.rglob('*'):
                if not path.is_file() or path.name.startswith('._'):
                    continue
                target = str(path.relative_to(source))
                if target.startswith('usr/share/overwall/'):
                    target = target.replace('usr/share/overwall/', 'usr/share/ucode/overwall/', 1)
                target = str(pathlib.PurePosixPath(prefix) / target)
                info = archive.gettarinfo(str(path), target)
                info.uid = info.gid = 0
                info.uname = info.gname = 'root'
                info.mode = 0o755 if target.startswith(('usr/bin/', 'usr/lib/overwall/', 'etc/init.d/')) else 0o644
                with path.open('rb') as file:
                    archive.addfile(info, file)
    archive.add(ROOT / 'tests/parser.uc', arcname='tmp/overwall-parser-test.uc')
subprocess.run(SSH + ['tar -C / -xf -'], input=data.getvalue(), check=True)
subprocess.run(SSH + ['ucode /tmp/overwall-parser-test.uc'], check=True)
subprocess.run(SSH + ['overwall status'], check=True)
subprocess.run(SSH + ['/etc/init.d/rpcd restart'], check=True)
