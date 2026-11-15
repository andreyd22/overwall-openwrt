// Run the complete installer in a disposable filesystem with package managers mocked.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../scripts/install.sh'), 'utf8');
let count = 0;
function scenario(name, options = {}) {
 const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'overwall-installer-flow-'));
 try {
  for (const dir of ['etc/opkg', 'etc/init.d', 'overlay/upper', 'var/opkg-lists', 'usr/bin']) fs.mkdirSync(path.join(tmp, dir), { recursive: true });
  fs.writeFileSync(path.join(tmp, 'etc/openwrt_release'), `DISTRIB_RELEASE=${options.apk ? '25.12.6' : '24.10.8'}\n`);
  fs.writeFileSync(path.join(tmp, 'etc/opkg.conf'), '');
  fs.writeFileSync(path.join(tmp, 'meminfo'), 'MemTotal: 256000 kB\n');
  fs.writeFileSync(path.join(tmp, 'etc/init.d/v2raya'), '', {mode:0o755});
  const plan = options.plan ?? (options.apk ? '( 1/12) Installing luci-app-overwall (0.1.2-r1)' : 'Installing luci-app-overwall (0.1.2-1) to root...');
  fs.writeFileSync(path.join(tmp, 'plan'), plan+'\n');
  fs.writeFileSync(path.join(tmp, 'var/opkg-lists/feed'), options.index ?? 'Package: luci-app-overwall\nVersion: 0.1.2-1\nSize: 15000\n\n');
  const script = source.replaceAll('opkg-key','opkg_key').replaceAll('/etc/',tmp+'/etc/').replaceAll('/overlay',tmp+'/overlay').replaceAll('/var/opkg-lists',tmp+'/var/opkg-lists').replaceAll('/usr/bin/xray',tmp+'/usr/bin/xray').replaceAll('/proc/meminfo',tmp+'/meminfo');
  fs.writeFileSync(path.join(tmp,'install.sh'),script);
  const wrapper = `
set -eu
id() { echo 0; }
uname() { echo aarch64; }
df() { case "$2" in */overlay) n=${options.free ?? 30720};; *) n=${options.temporary ?? 65536};; esac; printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\nmock 100000 0 %s 0%% /\\n' "$n"; }
opkg_key() { return 0; }
opkg() {
 case "$1" in
 update) return ${options.repoError ? 1 : 0};;
 --noaction) cat '${tmp}/plan'; return ${options.planError ? 1 : 0};;
 --tmp-dir) echo installed > '${tmp}/installed'; return ${options.installError ? 1 : 0};;
 *) echo 'Unexpected opkg call' >&2; return 97;;
 esac
}
apk() {
 case "$1 $2" in
 'update ') return 0;;
 'add --simulate') cat '${tmp}/plan'; return 0;;
 'info --size') printf 'luci-app-overwall installed size:\\n32 KiB\\n'; return 0;;
 'add --no-cache') echo installed > '${tmp}/installed'; return 0;;
 *) echo 'Unexpected apk call' >&2; return 98;;
 esac
}
set -- ${options.check ? '--check' : ''}
. '${tmp}/install.sh'
`;
  // APK update has no $2; the mock must tolerate that under set -u.
  const result = spawnSync('/bin/sh',['-c',wrapper.replace('"$1 $2"','"$1 ${2:-}"')],{encoding:'utf8',timeout:10000,killSignal:'SIGKILL'});
  assert.equal(result.error,undefined, name);
  const out=result.stdout+result.stderr;
  assert.equal(result.status,options.fail ? 1 : 0, name+'\n'+out);
  assert.equal(fs.existsSync(path.join(tmp,'installed')),options.calledInstall ?? (!options.fail && !options.check),name+' install mutation');
  for(const text of options.contains ?? []) assert.ok(out.includes(text),name+' missing '+text+'\n'+out);
  console.log('PASS '+name); count++;
 } finally {fs.rmSync(tmp,{recursive:true,force:true});}
}
scenario('24.10 existing core, 30 MiB', {contains:['v2rayA','Места достаточно','Overwall VPN установлен']});
scenario('24.10 existing core, 10 MiB', {free:10240});
scenario('check only', {check:true,contains:['Пакеты не устанавливались']});
scenario('not enough flash', {free:2200,fail:true,contains:['Не хватает']});
scenario('not enough tmp', {temporary:1024,fail:true,contains:['Недостаточно временного места']});
scenario('repository error', {repoError:true,fail:true,contains:['DNS','дату']});
scenario('dependency solver error', {planError:true,fail:true,contains:['kernel/kmod']});
scenario('unknown dependency size', {plan:'Installing other (1) to root...',fail:true,contains:['не сообщил установленный размер other']});
scenario('new core exceeds 30 MiB with reserve', {plan:'Installing xray-core (25.1.30-r1) to root...',index:'Package: xray-core\nVersion: 25.1.30-r1\nInstalled-Size: 27627520\nSize: 9841593\n\n',fail:true,contains:['Не хватает']});
scenario('repeat install', {plan:'Package luci-app-overwall (0.1.2-1) installed in root is up to date.',contains:['Все пакеты уже установлены']});
scenario('install failure', {installError:true,fail:true,calledInstall:true,contains:['Часть зависимостей могла установиться']});
scenario('25.12 APK padded plan', {apk:true});
console.log(`${count} installer flow scenarios passed`);
