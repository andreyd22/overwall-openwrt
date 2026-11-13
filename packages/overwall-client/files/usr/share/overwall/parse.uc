'use strict';

// Provider input is data. Never import routing, inbounds or executable hooks.
function fail(message) { die(message); }
function text(v, max) {
	if (type(v) != 'string' || !length(v) || length(v) > (max || 2097152)) fail('Invalid or oversized input');
	return trim(v);
}
function decode(v) {
	return replace(v || '', /%([a-fA-F0-9]{2})/g, (_, hex) => chr(int(hex, 16)));
}
function host(v) {
	if (type(v) != 'string' || !match(v, /^[a-zA-Z0-9][a-zA-Z0-9.:-]*$/) || length(v) > 253) fail('Invalid endpoint');
	return v;
}
function port(v) {
	if (!match('' + v, /^[0-9]+$/) || int(v) < 1 || int(v) > 65535) fail('Invalid port');
	return int(v);
}
function node(uri) {
	uri = text(uri, 16384);
	let fragments = split(uri, '#'), main = shift(fragments), label = join('#', fragments);
	let queries = split(main, '?'); main = shift(queries);
	let query = join('?', queries);
	let m = match(main, /^vless:\/\/([0-9a-fA-F-]+)@(\[[0-9a-fA-F:]+\]|[^:/?#]+):([0-9]+)$/);
	if (!m || !match(m[1], /^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$/)) fail('Invalid VLESS link');
	let q = {};
	for (let pair in split(query || '', '&')) {
		let parts = split(pair, '=');
		q[decode(shift(parts))] = decode(join('=', parts));
	}
	if (q.allowInsecure == '1' || q.allowInsecure == 'true' || q.insecure == '1' || q.insecure == 'true') fail('Insecure TLS is not supported');
	let network = q.type || 'tcp', security = q.security || 'none';
	if (index(['tcp', 'raw', 'ws', 'grpc', 'xhttp', 'httpupgrade'], network) < 0 || index(['none', 'tls', 'reality'], security) < 0) fail('Unsupported VLESS transport');
	let address = replace(replace(m[2], /^\[/, ''), /\]$/, '');
	let stream = { network, security };
	if (security == 'tls') stream.tlsSettings = { serverName: q.sni || address, allowInsecure: false, fingerprint: q.fp || 'chrome' };
	if (security == 'reality') {
		if (!q.pbk || !(q.sni || q.serverName)) fail('Missing Reality public key or SNI');
		stream.realitySettings = { publicKey: q.pbk, serverName: q.sni || q.serverName, shortId: q.sid || '', fingerprint: q.fp || 'chrome', spiderX: q.spx || '/' };
	}
	if (network == 'ws') stream.wsSettings = { path: q.path || '/', headers: q.host ? { Host: q.host } : {} };
	if (network == 'grpc') stream.grpcSettings = { serviceName: q.serviceName || '' };
	if (network == 'xhttp' || network == 'httpupgrade') stream[network + 'Settings'] = { path: q.path || '/', host: q.host || '', ...(network == 'xhttp' ? { mode: q.mode || 'auto' } : {}) };
	return { name: decode(label) || address, protocol: 'vless', outbound: {
		tag: 'proxy', protocol: 'vless', settings: { vnext: [{ address: host(address), port: port(m[3]), users: [{ id: m[1], encryption: 'none', ...(q.flow ? { flow: q.flow } : {}) }] }] }, streamSettings: stream
	} };
}
function jsonNode(o, name) {
	let target = o?.settings?.vnext?.[0], user = target?.users?.[0], st = o?.streamSettings || {};
	if (o?.protocol != 'vless' || !target || !user || length(o.settings.vnext) != 1 || length(target.users) != 1) fail('Only single-target VLESS outbounds are supported');
	let tls = st.tlsSettings || {}, reality = st.realitySettings || {};
	if (tls.allowInsecure || tls.allowInsecureIfPinnedPeerCertificate || tls.disableSystemRoot || o.proxySettings || o.mux?.enabled) fail('Unsafe or unsupported outbound options');
	let q = { type: st.network || 'tcp', security: st.security || 'none', flow: user.flow, sni: tls.serverName || reality.serverName, pbk: reality.publicKey, sid: reality.shortId, fp: tls.fingerprint || reality.fingerprint };
	let transport = st[(q.type == 'raw' ? 'tcp' : q.type) + 'Settings'] || {};
	q.path = transport.path; q.host = transport.host || transport.headers?.Host; q.serviceName = transport.serviceName; q.mode = transport.mode;
	// URI construction is internal; validate connection parameters through one path.
	let query = [];
	for (let key, value in q) if (value != null && value != '') push(query, key + '=' + replace(replace(replace('' + value, /%/g, '%25'), /&/g, '%26'), /#/g, '%23'));
	let address = host(target.address);
	let n = node('vless://' + user.id + '@' + (index(address, ':') >= 0 ? '[' + address + ']' : address) + ':' + port(target.port) + '?' + join('&', query));
	n.name = name || o.tag || address;
	return n;
}
function subscription(input) {
	let value = text(input), result = [];
	if (!match(value, /^(vless:\/\/|\[|\{)/)) {
		let decoded = b64dec(replace(replace(replace(value, /[[:space:]]/g, ''), /-/g, '+'), /_/g, '/'));
		if (!decoded) fail('Unsupported subscription format');
		value = trim(decoded);
	}
	if (match(value, /^(\[|\{)/)) {
		let data = json(value), items = type(data) == 'array' ? data : [data];
		for (let item in items) {
			if (type(item) == 'string') push(result, node(item));
			else if (item.outbounds) {
				for (let outbound in item.outbounds) if (outbound.protocol == 'vless') push(result, jsonNode(outbound, item.remarks || item.ps));
			} else push(result, jsonNode(item));
		}
	} else {
		for (let line in split(value, '\n')) if (trim(line) && !match(trim(line), /^#/)) push(result, node(trim(line)));
	}
	if (!length(result) || length(result) > 256) fail('Subscription must contain 1–256 VLESS servers');
	return result;
}
function key(v) {
	if (!match(v || '', /^[a-zA-Z0-9+/]{43}=$/) || length(b64dec(v) || '') != 32) fail('Invalid WireGuard key');
	return v;
}
function cidr(v) {
	if (!match(v, /^[0-9a-fA-F:.]+\/[0-9]+$/)) fail('Invalid network address');
	let parts = split(v, '/'), ipv6 = index(parts[0], ':') >= 0;
	if (int(parts[1]) > (ipv6 ? 128 : 32)) fail('Invalid prefix');
	if (!ipv6) { let octets = split(parts[0], '.'); if (length(octets) != 4) fail('Invalid IPv4 address'); for (let octet in octets) if (!match(octet, /^[0-9]{1,3}$/) || int(octet) > 255) fail('Invalid IPv4 address'); }
	return v;
}
function wireguard(input) {
	let section = '', conf = { interface: {}, peers: [] }, peer;
	for (let line in split(text(input, 65536), '\n')) {
		line = trim(replace(line, /[;#].*$/, ''));
		if (!line) continue;
		if (line == '[Interface]') { if (section) fail('Duplicate Interface'); section = 'interface'; continue; }
		if (line == '[Peer]') { if (!section) fail('Missing Interface'); peer = {}; push(conf.peers, peer); section = 'peer'; continue; }
		let m = match(line, /^([a-zA-Z]+)[[:space:]]*=[[:space:]]*(.*)$/);
		if (!m || !section) fail('Invalid WireGuard configuration');
		let allowed = section == 'interface' ? ['PrivateKey', 'Address', 'DNS', 'MTU', 'ListenPort'] : ['PublicKey', 'PresharedKey', 'Endpoint', 'AllowedIPs', 'PersistentKeepalive'];
		if (index(allowed, m[1]) < 0) fail('Unsupported WireGuard option: ' + m[1]);
		let target = section == 'interface' ? conf.interface : peer;
		if (target[m[1]] != null) fail('Duplicate WireGuard option');
		target[m[1]] = trim(m[2]);
	}
	if (length(conf.peers) != 1) fail('Exactly one WireGuard peer is supported');
	let iface = conf.interface; peer = conf.peers[0];
	key(iface.PrivateKey); key(peer.PublicKey); if (peer.PresharedKey) key(peer.PresharedKey);
	if (!iface.Address || !peer.Endpoint || !peer.AllowedIPs) fail('Missing WireGuard fields');
	iface.addresses = map(split(iface.Address, ','), v => cidr(trim(v)));
	peer.allowed = map(split(peer.AllowedIPs, ','), v => cidr(trim(v)));
	if (index(peer.allowed, '0.0.0.0/0') < 0) fail('Router VPN requires AllowedIPs = 0.0.0.0/0');
	let endpoint = match(peer.Endpoint, /^(\[[a-fA-F0-9:]+\]|[^:]+):([0-9]+)$/);
	if (!endpoint) fail('Invalid WireGuard endpoint');
	peer.host = host(replace(replace(endpoint[1], /^\[/, ''), /\]$/, '')); peer.port = port(endpoint[2]);
	if (iface.MTU && (!match(iface.MTU, /^[0-9]+$/) || int(iface.MTU) < 1280 || int(iface.MTU) > 1500)) fail('Invalid MTU');
	if (iface.ListenPort) port(iface.ListenPort);
	if (peer.PersistentKeepalive && (!match(peer.PersistentKeepalive, /^[0-9]+$/) || int(peer.PersistentKeepalive) > 65535)) fail('Invalid keepalive');
	if (iface.DNS) for (let dns in split(iface.DNS, ',')) if (!match(trim(dns), /^[0-9a-fA-F:.]+$/)) fail('DNS must be an IP address');
	return conf;
}
export { subscription, node, wireguard };
