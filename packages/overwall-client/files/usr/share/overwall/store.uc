'use strict';
import * as fs from 'fs';

const HOME = '/etc/overwall', RUN = '/var/run/overwall';
function init() {
	for (let dir in [HOME, RUN]) { fs.mkdir(dir, 0700); fs.chmod(dir, 0700); }
}
function read(name, runtime) {
	let raw = fs.readfile((runtime ? RUN : HOME) + '/' + name + '.json');
	if (!raw) return null;
	try { return json(raw); } catch (_) { die('Stored configuration is invalid'); }
}
function write(name, value, runtime) {
	init();
	let path = (runtime ? RUN : HOME) + '/' + name + '.json';
	let file = fs.open(path + '.new', 'w', 0600);
	if (!file || !file.write(sprintf('%J', value))) die('Cannot save configuration');
	file.close(); fs.chmod(path + '.new', 0600);
	if (!fs.rename(path + '.new', path)) die('Cannot replace configuration');
}
function remove(name, runtime) { fs.unlink((runtime ? RUN : HOME) + '/' + name + '.json'); }
function popen(argv) {
	return fs.popen(join(' ', map(argv, arg => "'" + replace('' + arg, /'/g, "'\\''") + "'")) + ' 2>/dev/null', 'r');
}
function run(argv) {
	let pipe = popen(argv);
	if (!pipe) die('Cannot start helper');
	let output = pipe.read('all'), code = pipe.close();
	if (code != 0) die('System operation failed');
	return output || '';
}
function random() {
 let file = fs.open('/dev/urandom', 'r');
 if (!file) die('Secure random source unavailable');
 let bytes = file.read(32); file.close();
 if (length(bytes) != 32) die('Secure random source failed');
 return replace(replace(replace(b64enc(bytes), /\+/g, '-'), /\//g, '_'), /=/g, '');
}
function foregroundWaiting() {
 for (let file in fs.glob(RUN + '/foreground-*') || []) {
  let pid = match(file, /\/foreground-([0-9]+)$/);
  if (pid && fs.stat('/proc/' + pid[1])) return true;
  fs.unlink(file);
 }
 return false;
}
function state() { return read('state') || { version: 1, sources: [], network: 'lan', autostart: false, selected: null }; }
export { HOME, RUN, init, read, write, remove, popen, run, random, state, foregroundWaiting };
