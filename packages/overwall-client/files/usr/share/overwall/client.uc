'use strict';
import * as store from 'overwall.store';
import * as parse from 'overwall.parse';
import * as http from 'overwall.http';
import * as network from 'overwall.network';

function current(state) {
	for (let source in state.sources) if (source.id == state.selected) return source;
	return null;
}
function checkedName(name) {
	if (type(name) != 'string' || !length(trim(name)) || length(name) > 100 || match(name, /[[:cntrl:]]/)) die('Enter a name (1–100 characters)');
	return trim(name);
}
function refreshAccount() {
	let account = http.api('/me', null, true), wg = http.api('/wireguard', null, true);
	let state = store.state(), source;
	for (let entry in state.sources) if (entry.kind == 'overwall') source = entry;
	if (!source) { source = { id: store.random(), name: 'Overwall', kind: 'overwall', nodes: [] }; push(state.sources, source); }
	source.user_id = account.id; source.access = account.access; source.wireguard = wg; source.email = account.email; source.updated_at = time();
	let cached = filter(source.nodes || [], n => n.protocol == 'vless');
	source.nodes = [];
	for (let server in account.servers || []) {
		let node = parse.node(server.uri); node.name = server.name; node.id = 'vless:' + server.id; push(source.nodes, node);
	}
	if (account.access.state != 'active') source.nodes = cached;
	for (let profile in wg.profiles || []) push(source.nodes, { id: 'wireguard:' + profile.id, name: profile.name, protocol: 'wireguard', slot: profile.id, location: profile.location, ownership: profile.ownership, state: profile.state });
	store.write('state', state);
	return source;
}
// All commands and watcher ticks hold the CLI flock. Keep release receipts in
// /etc, not /var/run: a reboot must not forget a stopped device's assignment.
function drainRelease() {
 let receipt = store.read('wg-binding');
 if (!receipt?.pending) return;
 let session = store.read('session');
 if (!session) die('VPN отключён, освобождение слота ожидается');
 if (receipt.owner != session.device_id) {
  if (!receipt.account || receipt.installation != store.read('installation')?.id || '' + http.api('/me', null, true).id != '' + receipt.account) die('VPN отключён, освобождение слота ожидается');
  receipt.owner = session.device_id; store.write('wg-binding', receipt);
 }
 if (receipt.discover) {
  let profiles = http.api('/wireguard', null, true).profiles;
  receipt.releases = [];
  for (let p in profiles || []) if (p.ownership?.state == 'mine') push(receipt.releases, { slot: p.id, version: p.ownership.version });
  receipt.discover = false; store.write('wg-binding', receipt);
 }
 while (length(receipt.releases || [])) {
  let item = receipt.releases[0];
  try { http.api('/wireguard/' + item.slot + '/release', { version: item.version }, true); }
  catch (e) { if (index('' + e, 'wireguard_binding_changed') < 0) die('VPN отключён, освобождение слота ожидается'); }
  shift(receipt.releases); store.write('wg-binding', receipt);
  // Update only the confirmed assignment; never erase a newer owner/version.
  let state = store.state();
  for (let source in state.sources) if (source.kind == 'overwall')
   for (let node in source.nodes || []) if ('' + node.slot == '' + item.slot && node.ownership?.state == 'mine' && node.ownership.version == item.version) node.ownership = { state: 'free' };
  store.write('state', state);
 }
 store.remove('wg-binding'); store.remove('release-notice');
}
function stopOwned(discover) {
 let state = store.state(), source = current(state), node = source?.nodes[state.node || 0];
 state.autostart = false; state.protected = false; store.write('state', state);
 network.closePortal(); network.stop(true); // Must confirm teardown before release.
 let receipt = store.read('wg-binding'), session = store.read('session');
 if (!receipt && session && (discover || (source?.kind == 'overwall' && node?.protocol == 'wireguard')))
  receipt = { owner: session.device_id, account: source?.user_id, installation: store.read('installation')?.id, discover: true };
 if (receipt) { receipt.pending = true; store.write('wg-binding', receipt); }
 store.remove('connection', true); store.remove('intent', true);
 if (receipt) {
  store.write('release-notice', { pending: true });
  store.write('release-kick', { at: time() }, true);
 }
}
function connect() {
	drainRelease();
	let state = store.state(), source = current(state);
	if (!source) die('Select a subscription or profile');
	let index = int(state.node || 0), node = source.nodes[index];
	if (!node) die('Select a server');
	if (source.kind == 'overwall') {
		// Fresh server proof is required before an Overwall connection or recovery.
		source = refreshAccount();
		if (state.node_id) { node = null; for (let entry in source.nodes) if (entry.id == state.node_id) node = entry; }
		else node = source.nodes[index];
		if (!node) die('Server list changed; select a server again');
		if (node.protocol == 'vless' && source.access.state != 'active') { network.portal(source.access.state); return; }
		if (node.protocol == 'wireguard') {
			if (source.wireguard.state == 'access_required') { network.portal('access_required'); return; }
            let session = store.read('session');
            // Persist intent before HTTP so a lost claim ACK is recoverable.
            store.write('wg-binding', { owner: session.device_id, account: source.user_id, installation: store.read('installation')?.id, pending: true, discover: true });
            let assignment = http.api('/wireguard/' + node.slot + '/claim', {}, true);
            store.write('wg-binding', { owner: session.device_id, account: source.user_id, installation: store.read('installation')?.id,
                pending: false, releases: [{ slot: node.slot, version: assignment.ownership.version }] });
			let saved = store.state();
			for (let entry in saved.sources) if (entry.id == source.id) for (let profile in entry.nodes) if (profile.slot == node.slot && profile.protocol == 'wireguard') profile.ownership = assignment.ownership;
			store.write('state', saved);
			let config = http.api('/wireguard/' + node.slot + '/configuration', null, true);
			node = { ...node, configuration: parse.wireguard(config.configuration) };
		}
	}
    try { network.closePortal(); network.connect(node); }
    catch (e) { stopOwned(false); die('Connection failed'); }
	store.remove('health', true); store.remove('notice', true);
	store.write('connection', { state: 'connected', source_id: source.id, node: index, protocol: node.protocol, checked_at: time() }, true);
}
function tick() {
 if (store.foregroundWaiting()) return;
 // Bound background lock occupancy; foreground API requests retain their timeout.
 http.background();
 try { drainRelease(); } catch (_) { store.write('release-notice', { pending: true }); }
 if (store.foregroundWaiting()) return;
	let state = store.state(), connection = store.read('connection', true), source = current(state), portal = store.read('portal', true);
	let last = store.read('poll', true);
	if (last && time() - last.at < (portal ? 15 : 60)) return;
	store.write('poll', { at: time() }, true);
	if (!connection && !portal) return;
	if (source?.kind == 'overwall') {
		try {
			source = refreshAccount();
			let protocol = connection?.protocol || store.read('intent', true)?.protocol || 'vless';
			let allowed = protocol == 'wireguard' ? source.wireguard.state != 'access_required' : source.access.state == 'active';
			if (!allowed) {
				store.write('intent', { protocol }, true);
				if (!portal) network.portal(protocol == 'wireguard' ? 'access_required' : source.access.state);
				store.write('connection', { ...connection, state: 'restricted', protocol }, true);
			} else if (portal) connect();
		} catch (_) {
			// Unknown API status never turns into a payment/traffic error.
			store.write('notice', { error: 'Account status unavailable; existing authorization preserved', at: time() }, true);
		}
	}
 if (connection?.state == 'connected' && !store.read('portal', true)) {
  let previous = store.read('health', true), good = network.healthy(connection.protocol);
  if (store.foregroundWaiting()) return;
  let failures = good ? 0 : (previous?.failures || 0) + 1;
  store.write('health', { failures, checked_at: time(), healthy: good }, true);
  if (failures >= 3) {
   network.portal('connection_failed');
   store.write('connection', { ...connection, state: 'error', reason: 'connection_failed' }, true);
  }
 }

}
function command(action, input) {
	let state = store.state(); input = input || {};
	if (action == 'status') {
		let info = store.read('connection', true) || { state: 'disconnected' };
		return { ...info, version: '0.1.2', network: state.network, autostart: state.autostart, protected: !!state.protected, selected: state.selected, node: state.node || 0, signed_in: !!store.read('session'), portal: store.read('portal', true), release_pending: !!store.read('wg-binding')?.pending, notice: store.read('notice', true), sources: map(state.sources, source => ({ id: source.id, name: source.name, kind: source.kind, updated_at: source.updated_at, access: source.access, email: source.email, wireguard: source.wireguard ? {state:source.wireguard.state,traffic_unlimited:source.wireguard.traffic_unlimited,device_limit:source.wireguard.device_limit} : null, usage: source.usage, nodes: map(source.nodes, node => ({ name: node.name, protocol: node.protocol, slot: node.slot, location: node.location, ownership: node.ownership, state: node.state, details: node.configuration ? {address:node.configuration.interface.Address,dns:node.configuration.interface.DNS,endpoint:node.configuration.peers[0].Endpoint} : null })) })) };
	}
	if (action == 'add') {
		if (length(state.sources) >= 32) die('Maximum 32 subscriptions');
		let source = { id: store.random(), name: checkedName(input.name), kind: input.kind, updated_at: time() };
		if (input.kind == 'wireguard') source.nodes = [{ name: source.name, protocol: 'wireguard', configuration: parse.wireguard(input.value) }];
		else if (input.kind == 'url' || input.kind == 'text') {
			let data = input.value;
			if (input.kind == 'url') { source.url = input.value; data = http.external(source.url).data; }
			source.nodes = parse.subscription(data);
		} else die('Unsupported import type');
		push(state.sources, source); store.write('state', state); return { success: true };
	}
	if (action == 'refresh') {
		let source = null;
		for (let entry in state.sources) if (entry.id == input.id) source = entry;
		if (!source) die('Subscription not found');
		if (source.kind == 'overwall') refreshAccount();
		else {
			if (source.kind != 'url') die('Only URL subscriptions can be refreshed');
			let response = http.external(source.url), nodes = parse.subscription(response.data);
			source.nodes = nodes; source.updated_at = time(); store.write('state', state);
		}
		return { success: true };
	}
	if (action == 'remove') {
		if (input.id == state.selected) { stopOwned(false); state = store.state(); state.selected = null; }
		state.sources = filter(state.sources, s => s.id != input.id); store.write('state', state); return { success: true };
	}
	if (action == 'settings') {
		if (input.network != state.network && (store.read('connection', true) || store.read('portal', true))) die('Disconnect before changing the network');
		if (!match(input.network || '', /^[a-zA-Z0-9_]{1,32}$/)) die('Invalid network name');
		state.network = input.network; state.autostart = !!input.autostart; store.write('state', state);
		return { success: true };
	}
	if (action == 'connect') {
		let source;
		for (let entry in state.sources) if (entry.id == input.id) source = entry;
		if (!source || !source.nodes[int(input.node)]) die('Select a server');
		let net = network.selected();
        stopOwned(true); drainRelease(); state = store.state();
		state.selected = source.id; state.node = int(input.node); state.node_id = source.nodes[state.node].id; state.protected = true; state.device = net.device; store.write('state', state);
		network.guard('closed', net.device);
		try { connect(); } catch (e) { stopOwned(false); store.write('connection', { state: 'error', source_id: source.id, protocol: source.nodes[state.node].protocol }, true); die('Connection failed'); }
		return { success: true };
	}
 if (action == 'disconnect') { stopOwned(false); return { success: true, release_pending: !!store.read('wg-binding')?.pending }; }
 if (action == 'release') { stopOwned(true); return { success: true, release_pending: !!store.read('wg-binding')?.pending }; }
	if (action == 'pair') {
		let installation = store.read('installation');
		if (!installation) { installation = { id: store.random() }; store.write('installation', installation); }
		let pairing = http.api('/tv/request', { platform: 'openwrt', installation_id: installation.id });
		store.write('pairing', { ...pairing, expires_at: time() + pairing.expires_in }, true);
		return { verification_uri: pairing.verification_uri, user_code: pairing.user_code, expires_in: pairing.expires_in, poll_interval: pairing.poll_interval, qr_svg: store.run(['/usr/bin/qrencode', '-t', 'SVG', '-o', '-', pairing.verification_uri]) };
	}
	if (action == 'pair_poll') {
		let pairing = store.read('pairing', true);
		if (!pairing || pairing.expires_at <= time()) die('Pairing code expired');
		if (pairing.next_poll > time()) return { pending: true };
		pairing.next_poll = time() + 5; store.write('pairing', pairing, true);
		let session;
		try { session = http.api('/tv/token', { device_code: pairing.device_code, device_secret: pairing.device_secret }); } catch (_) { return { pending: true }; }
		store.write('session', { ...session, refresh_at: time() + session.expires_in - 60 }); store.remove('pairing', true);
		refreshAccount(); return { success: true };
	}
	if (action == 'logout') {
		let session = store.read('session');
		if (current(state)?.kind == 'overwall') { stopOwned(true); drainRelease(); }
		if (session) http.api('/devices/' + session.device_id, null, true, 'DELETE');
		store.remove('session'); state = store.state(); state.sources = filter(state.sources, s => s.kind != 'overwall'); store.write('state', state);
		return { success: true };
	}
	if (action == 'suspend') {
		if (state.protected && state.device) network.guard('closed', state.device);
		network.closePortal(); network.stop(false); store.remove('connection', true); return { success: true };
	}
	if (action == 'tick') { tick(); return { success: true }; }
	if (action == 'boot') { if (state.autostart && state.selected) connect(); return { success: true }; }
	die('Unknown operation');
}
export { command };
