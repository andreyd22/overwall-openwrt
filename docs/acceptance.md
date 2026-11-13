# Release acceptance

Status is recorded separately for each release, architecture and test layer.
A successful package build is not proof of a working VPN, device login, payment,
or captive portal on a phone. Fixtures use no customer identities or VPN keys.

| Check | Required evidence |
| --- | --- |
| Import formats and rejected unsafe configuration | `tests/parser.uc` on the guest |
| LuCI status and write-only mutations | HTTP/ubus authorization tests |
| QR pairing and one-time installation proof | Real Valkey + HTTP backend tests; separate live approval |
| Account isolation and expired/revoked tokens | Backend security tests |
| VLESS TCP and UDP | Two LAN clients reach isolated WAN origin |
| VLESS failure | Both LAN clients lose TCP/UDP without direct fallback |
| WireGuard TCP and UDP | Two LAN clients reach isolated WAN origin; handshake |
| WireGuard failure | Interface removal blocks both clients |
| DNS | Requests traverse the selected tunnel; no WAN DNS from clients |
| IPv6 | No forwarding out of the selected network |
| Reboot and firewall reload | Guard persists; automatic connection restores only when enabled |
| Import update failure | Previous working configuration retained |
| Overwall exhaustion/recovery | Protocol-specific API proof; both clients enter/leave portal |
| Independent source error | Diagnostics and optional Overwall link; no quota coupling |
| Payment through portal | Website, login, provider and bank return flow all work |
| Package installation/update/removal | APK 25.12 and IPK 24.10 guests |
| LuCI desktop/mobile | Real browser, dialogs, all controls, no horizontal clipping |
| Portal OS notification | Android/iOS/Windows/macOS checked separately |
| Public artifacts | No secrets; signatures and full downloads verified |

Do not mark pending checks as passed. Publish exact tested versions, commit and
package hashes in the dated acceptance report. Physical router throughput and
OS captive-window behavior require their own evidence.
