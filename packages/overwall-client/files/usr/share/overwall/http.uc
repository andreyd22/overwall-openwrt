'use strict';
import * as fs from 'fs';
import * as store from 'overwall.store';

const ORIGIN = 'https://overwall.online';
function request(url, method, body, token, pinned) {
	store.init();
	if (!match(url, /^https?:\/\/[^\r\n]+$/) || length(url) > 4096 || match(url, /[[:cntrl:][:space:]]/)) die('Invalid URL');
	let id = store.random(), root = store.RUN + '/http-' + id;
	let args = ['/usr/bin/curl', '--silent', '--show-error', '--connect-timeout', '10', '--max-time', '25', '--max-filesize', '2097152', '--max-redirs', '0', '--proto', '=http,https', '--dump-header', root + '.headers', '--output', root + '.body', '--write-out', '%{http_code}', '--request', method || 'GET'];
	if (pinned) push(args, '--resolve', pinned);
	// Credentials never appear in process arguments or redirects.
	let config = '';
	if (token) {
		if (!match(token, /^[a-zA-Z0-9_.-]+$/)) die('Invalid credential');
		config += 'header = "Authorization: Bearer ' + token + '"\n';
	}
	if (body != null) {
		fs.writefile(root + '.request', sprintf('%J', body)); fs.chmod(root + '.request', 0600);
		push(args, '--header', 'Content-Type: application/json', '--data-binary', '@' + root + '.request');
	}
	fs.writefile(root + '.config', config); fs.chmod(root + '.config', 0600);
	push(args, '--config', root + '.config', '--url', url);
	let status = 0, data = '', headers = '';
	try {
		let proc = store.popen(args);
		status = int(proc.read('all')); let code = proc.close();
		if (code != 0) die('Network request failed');
		data = fs.readfile(root + '.body') || ''; headers = fs.readfile(root + '.headers') || '';
		if (length(data) > 2097152) die('Response too large');
	} catch (e) { for (let suffix in ['.config', '.request', '.body', '.headers']) fs.unlink(root + suffix); die('Network request failed'); }
	for (let suffix in ['.config', '.request', '.body', '.headers']) fs.unlink(root + suffix);
	return { status, data, headers };
}
function api(path, body, authenticated, method) {
	if (!match(path, /^\/[a-zA-Z0-9_\/-]+$/)) die('Invalid API path');
	let session = store.read('session');
	if (authenticated && !session) die('Sign in to Overwall first');
	if (authenticated && session.refresh_at <= time()) {
		let nonce = session.refresh_nonce || store.random(); session.refresh_nonce = nonce; store.write('session', session);
		let response = request(ORIGIN + '/api/client/v1/auth/refresh', 'POST', { refresh_token: session.refresh_token, request_id: nonce });
		let data = json(response.data);
		if (response.status != 200) die('Cannot refresh authorization; existing session preserved');
		session = { ...data, refresh_at: time() + data.expires_in - 60 }; store.write('session', session);
	}
	let response = request(ORIGIN + '/api/client/v1' + path, method || (body != null ? 'POST' : 'GET'), body, authenticated ? session.access_token : null);
	if (response.status == 204) return {};
	let data;
	try { data = json(response.data); } catch (_) { die('Invalid API response'); }
	if (response.status < 200 || response.status >= 300) die(data?.error == 'wireguard_binding_changed' ? 'wireguard_binding_changed' : 'API request failed (' + response.status + ')');
	return data;
}
function external(url) {
	let m = match(url, /^(https?):\/\/([a-zA-Z0-9.-]+)(:([0-9]+))?(\/[^#]*)?$/);
	if (!m || m[2] == 'localhost' || match(m[2], /(^|\.)localhost$/) || index(m[2], '..') >= 0) die('Use a public HTTP(S) subscription URL without credentials');
	let port = m[4] ? int(m[4]) : m[1] == 'https' ? 443 : 80;
	if (port < 1 || port > 65535) die('Invalid port');
	let raw = trim(store.run(['/usr/bin/resolveip', '-4', '-t', '5', m[2]])), addresses = split(raw, '\n');
	let ip = addresses[0], parts = split(ip, '.');
	if (length(parts) != 4 || !match(ip, /^[0-9.]+$/)) die('Cannot resolve subscription host');
	let a = int(parts[0]), b = int(parts[1]);
	if (a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 100 && b >= 64 && b <= 127) || (a == 198 && (b == 18 || b == 19))) die('Local and service addresses are not subscription sources');
	let response = request(url, 'GET', null, null, m[2] + ':' + port + ':' + ip);
	if (response.status != 200) die('Subscription server returned an error; redirects are not followed');
	return response;
}
export { ORIGIN, api, external };
