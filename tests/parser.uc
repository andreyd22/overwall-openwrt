'use strict';
import { node, subscription, wireguard } from 'overwall.parse';

let count = 0;
function ok(condition, name) { if (!condition) die('FAIL: ' + name); count++; }
function rejects(fn, name) { let failed = false; try { fn(); } catch (_) { failed = true; } ok(failed, name); }
const uri = 'vless://00000000-0000-4000-8000-000000000001@192.0.2.1:443?security=tls&type=ws&path=%2Fvpn#Fixture';
ok(node(uri).outbound.streamSettings.wsSettings.path == '/vpn', 'percent-encoded transport');
ok(node(uri).outbound.streamSettings.tlsSettings.allowInsecure == false, 'verified TLS');
ok(length(subscription(uri)) == 1, 'VLESS input');
ok(length(subscription(b64enc(uri))) == 1, 'Base64 input');
let outbound = node(uri).outbound;
ok(length(subscription(sprintf('%J', { inbounds: [{ port: 22 }], routing: { arbitrary: true }, outbounds: [outbound] }))) == 1, 'Xray outbound extraction');
ok(subscription(sprintf('%J', { outbounds: [outbound] }))[0].outbound.inbounds == null, 'foreign listeners not imported');
ok(node(uri + '&allowInsecure=true').outbound.streamSettings.tlsSettings.allowInsecure == false, 'fragment is not a TLS option');
rejects(() => node(replace(uri, '?security=tls', '?allowInsecure=true&security=tls')), 'insecure TLS rejected');
rejects(() => subscription('vmess://anything'), 'unsupported protocol');
rejects(() => subscription('not a subscription'), 'invalid Base64');
let unsafe = { ...outbound, streamSettings: { security: 'tls', tlsSettings: { allowInsecure: true } } };
rejects(() => subscription(sprintf('%J', unsafe)), 'unsafe JSON TLS');
const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const conf = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.7.0.2/32\nDNS = 9.9.9.9\n[Peer]\nPublicKey = ' + key + '\nEndpoint = vpn.example.invalid:51820\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25';
ok(wireguard(conf).peers[0].port == 51820, 'WireGuard parse');
rejects(() => wireguard(conf + '\nPostUp = touch /tmp/unsafe'), 'executable hook rejected');
rejects(() => wireguard(replace(conf, '10.7.0.2/32', '999.1.1.1/32')), 'invalid address');
rejects(() => wireguard(replace(conf, '0.0.0.0/0', '10.0.0.0/8')), 'partial tunnel rejected');
rejects(() => wireguard(conf + '\nPublicKey = ' + key), 'duplicate key rejected');
rejects(() => wireguard(replace(conf, key, 'bad')), 'invalid key');
printf('PASS %d parser and import safety checks\n', count);
