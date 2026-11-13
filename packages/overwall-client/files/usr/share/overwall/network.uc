'use strict';
import * as fs from 'fs';
import { cursor } from 'uci';
import * as store from 'overwall.store';

const LOCAL = '224.0.0.0/4, 255.255.255.255/32';
function section(uci, config, kind, id, values) {
 uci.set(config, id, kind);
 for (let key, value in values) uci.set(config, id, key, value);
}
function call(args) { return store.run(args); }
function quiet(args) { try { store.run(args); return true; } catch (_) { return false; } }
function selected() {
	let state = store.state(), name = state.network;
	if (!match(name || '', /^[a-zA-Z0-9_]{1,32}$/) || index(['wan', 'wan6', 'loopback', 'ow_wg'], name) >= 0) die('Select a LAN or guest network');
	let info = json(call(['/bin/ubus', 'call', 'network.interface.' + name, 'status']));
	let device = info.l3_device;
	if (!info.up || !match(device || '', /^[a-zA-Z0-9_.:-]{1,32}$/)) die('Selected network is down');
	let uci = cursor(), zone;
	uci.foreach('firewall', 'zone', section => {
		let networks = type(section.network) == 'array' ? section.network : split(section.network || '', ' ');
		if (index(networks, name) >= 0) zone = section.name;
	});
	if (!zone || !match(zone, /^[a-zA-Z0-9_]{1,32}$/)) die('Selected network needs a firewall zone');
	return { name, device, zone };
}
function rules(content) {
	let path = store.RUN + '/firewall.nft';
	fs.writefile(path, content); fs.chmod(path, 0600);
	quiet(['/usr/sbin/nft', 'add', 'table', 'inet', 'overwall']);
	call(['/usr/sbin/nft', '-c', '-f', path]);
	// Each replacement is one atomic nft transaction; the guard is never opened.
	call(['/usr/sbin/nft', '-f', path]);
}
function guard(mode, device, portalIPs) {
	let pre = '', forward = '', extra = '';
	if (mode == 'vless') {
		pre = `chain capture { type filter hook prerouting priority -150; policy accept;
			iifname "${device}" meta nfproto ipv4 meta l4proto { tcp, udp } th dport 53 meta mark set 0x5188 tproxy ip to :1053 accept
			iifname "${device}" fib daddr type local return
			iifname "${device}" ip daddr { ${LOCAL} } return
			iifname "${device}" meta nfproto ipv4 meta l4proto { tcp, udp } meta mark set 0x5188 tproxy ip to :12345 accept
		}`;
	}
	if (mode == 'wireguard') forward += `iifname "${device}" oifname "ow_wg" accept\n`;
	if (mode == 'portal' && length(portalIPs || [])) {
		extra = 'set garden { type ipv4_addr; elements = { ' + join(', ', portalIPs) + ' }; }';
		forward += `iifname "${device}" ip daddr @garden tcp dport 443 accept\n`;
	}
	if (mode == 'portal') pre = `chain portal_capture { type nat hook prerouting priority dstnat; policy accept; iifname "${device}" tcp dport 80 redirect to :2050; }`;
	forward += `iifname "${device}" oifname "${device}" accept\niifname "${device}" reject with icmpx type admin-prohibited`;
	rules(`flush table inet overwall\ntable inet overwall { ${extra}
		${pre}
		chain protect { type filter hook forward priority -5; policy accept;
			iifname "${device}" meta nfproto ipv6 reject with icmpx type admin-prohibited
			${forward}
		}
	}`);
}
function firewall(net, enabled) {
	let uci = cursor();
	for (let id in ['ow_input', 'ow_zone', 'ow_forward', 'ow_portal']) uci.delete('firewall', id);
	if (enabled) {
		section(uci, 'firewall', 'rule', 'ow_input', { name: 'Overwall transparent listener', src: net.zone, proto: 'tcp udp', mark: '0x5188', family: 'ipv4', target: 'ACCEPT' });
		section(uci, 'firewall', 'zone', 'ow_zone', { name: 'ow_vpn', network: ['ow_wg'], input: 'REJECT', output: 'ACCEPT', forward: 'REJECT', masq: '1', mtu_fix: '1' });
		section(uci, 'firewall', 'forwarding', 'ow_forward', { src: net.zone, dest: 'ow_vpn' });
	}
	uci.commit('firewall'); call(['/etc/init.d/firewall', 'reload']);
}
function cleanupRoutes() {
	for (let priority in ['11080', '11081', '11082']) quiet(['/sbin/ip', '-4', 'rule', 'del', 'priority', priority]);
	for (let table in ['51880', '51881']) quiet(['/sbin/ip', '-4', 'route', 'flush', 'table', table]);
}
function stop(removeGuard) {
	quiet(['/etc/init.d/overwall-tunnel', 'stop']);
	quiet(['/sbin/ifdown', 'ow_wg']); cleanupRoutes();
	if (removeGuard) {
		quiet(['/usr/sbin/nft', 'delete', 'table', 'inet', 'overwall']);
		firewall(null, false);
		let uci = cursor(); uci.delete('network', 'ow_wg'); uci.delete('network', 'ow_peer'); uci.commit('network');
	}
	store.remove('tunnel', true);
}
function connect(node) {
	let net = selected();
	guard('closed', net.device); stop(false); firewall(net, true);
	if (node.protocol == 'vless') {
		let conf = { log: { loglevel: 'none' }, inbounds: [
			{ tag: 'health', listen: '127.0.0.1', port: 10808, protocol: 'socks', settings: { auth: 'noauth', udp: false } },
			{ tag: 'transparent', listen: '0.0.0.0', port: 12345, protocol: 'dokodemo-door', settings: { network: 'tcp,udp', followRedirect: true }, streamSettings: { sockopt: { tproxy: 'tproxy' } } },
			{ tag: 'dns', listen: '0.0.0.0', port: 1053, protocol: 'dokodemo-door', settings: { address: '9.9.9.9', port: 53, network: 'tcp,udp' }, streamSettings: { sockopt: { tproxy: 'tproxy' } } }
		], outbounds: [node.outbound] };
		store.write('xray', conf, true);
		call(['/usr/bin/xray', 'run', '-test', '-config', store.RUN + '/xray.json']);
		call(['/sbin/ip', '-4', 'route', 'add', 'local', '0.0.0.0/0', 'dev', 'lo', 'table', '51880']);
		call(['/sbin/ip', '-4', 'rule', 'add', 'priority', '11080', 'fwmark', '0x5188', 'lookup', '51880']);
		call(['/etc/init.d/overwall-tunnel', 'start']); guard('vless', net.device);
	} else if (node.protocol == 'wireguard') {
		let conf = node.configuration, iface = conf.interface, peer = conf.peers[0], uci = cursor();
		uci.delete('network', 'ow_wg'); uci.delete('network', 'ow_peer');
		section(uci, 'network', 'interface', 'ow_wg', { proto: 'wireguard', private_key: iface.PrivateKey, addresses: filter(iface.addresses, a => index(a, ':') < 0), mtu: iface.MTU || '1420', ip4table: '51881' });
		section(uci, 'network', 'wireguard_ow_wg', 'ow_peer', { public_key: peer.PublicKey, ...(peer.PresharedKey ? { preshared_key: peer.PresharedKey } : {}), endpoint_host: peer.host, endpoint_port: '' + peer.port, allowed_ips: peer.allowed, route_allowed_ips: '0', persistent_keepalive: peer.PersistentKeepalive || '25' });
		uci.commit('network'); fs.chmod('/etc/config/network', 0600);
		call(['/etc/init.d/network', 'reload']); call(['/sbin/ifup', 'ow_wg']);
		let up = false;
		for (let i = 0; i < 15; i++) {
			if (quiet(['/sbin/ip', 'link', 'show', 'ow_wg'])) { up = true; break; }
			sleep(1000);
		}
		if (!up) die('WireGuard interface did not start');
		call(['/sbin/ip', '-4', 'route', 'replace', 'default', 'dev', 'ow_wg', 'table', '51881']);
		call(['/sbin/ip', '-4', 'rule', 'add', 'priority', '11081', 'iif', net.device, 'lookup', '51881']);
		call(['/sbin/ip', '-4', 'rule', 'add', 'priority', '11082', 'oif', 'ow_wg', 'lookup', '51881']);
		guard('wireguard', net.device);
		// LAN DNS must traverse the same tunnel, including requests to the router.
		let dns = trim(split(iface.DNS || '9.9.9.9', ',')[0]);
		if (index(dns, ':') >= 0) die('An IPv4 DNS server is required');
		call(['/usr/sbin/nft', 'add', 'chain', 'inet', 'overwall', 'dns', '{ type nat hook prerouting priority dstnat; policy accept; }']);
		call(['/usr/sbin/nft', 'add', 'rule', 'inet', 'overwall', 'dns', 'iifname', net.device, 'meta', 'l4proto', '{ tcp, udp }', 'th', 'dport', '53', 'dnat', 'ip', 'to', dns]);
	} else die('Unsupported VPN protocol');
	store.write('tunnel', { protocol: node.protocol, network: net.name, device: net.device, started_at: time() }, true);
}
function portal(reason) {
	let net = selected(); guard('closed', net.device); stop(false);
	let addresses = [];
	try {
		for (let ip in split(trim(call(['/usr/bin/resolveip', '-4', '-t', '5', 'overwall.online'])), '\n')) if (match(ip, /^[0-9.]+$/)) push(addresses, ip);
	} catch (_) {}
	guard('portal', net.device, addresses);
	store.write('portal', { reason, at: time() }, true);
	let uci = cursor();
	section(uci, 'firewall', 'rule', 'ow_portal', { name: 'Overwall captive portal and DNS', src: net.zone, proto: 'tcp udp', dest_port: '53 2050', target: 'ACCEPT' });
	uci.commit('firewall'); call(['/etc/init.d/firewall', 'reload']);
	fs.mkdir('/var/run/overwall-public', 0755); fs.chmod('/var/run/overwall-public', 0755);
	fs.writefile('/var/run/overwall-public/index.html', fs.readfile('/usr/lib/overwall/portal.html'));
	fs.writefile('/var/run/overwall-public/reason.json', sprintf('%J', { reason }));
	fs.chmod('/var/run/overwall-public/index.html', 0644); fs.chmod('/var/run/overwall-public/reason.json', 0644);
	call(['/etc/init.d/overwall-portal', 'restart']);
}
function closePortal() {
 if (store.read('portal', true)) {
  quiet(['/etc/init.d/overwall-portal', 'stop']);
  let uci = cursor(); uci.delete('firewall', 'ow_portal'); uci.commit('firewall');
 }
 store.remove('portal', true);
}

function healthy(protocol) {
 let args = ['/usr/bin/curl', '--silent', '--fail', '--connect-timeout', '5', '--max-time', '8', '--head', '--output', '/dev/null'];
 if (protocol == 'vless') push(args, '--socks5-hostname', '127.0.0.1:10808');
 else if (protocol == 'wireguard') push(args, '--interface', 'ow_wg');
 else return false;
 let base = args;
 for (let url in ['https://cp.cloudflare.com/generate_204', 'https://connectivitycheck.gstatic.com/generate_204']) {
  let probe = [...base, '--url', url]; if (quiet(probe)) return true;
 }
 return false;
}
export { selected, guard, connect, stop, portal, closePortal, healthy };
