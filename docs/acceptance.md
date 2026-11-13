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

## 0.1.1, 13.11.2026 — WireGuard release

Новая политика: обычное отключение и переключение освобождают прежний слот.
Очередь в /etc/overwall переживает потерю API и перезагрузку. Команды и watcher
используют существующий flock. Перед release проверяются остановка Xray и
удаление ow_wg; при ошибке привязка сохраняется. Выход сначала освобождает,
затем отзывает сессию. Временная потеря сети сохраняет назначение.

Проверено в изолированном QEMU: parser17 PASS; TLS/real-backend pairing,
account isolation/ограничение и recovery PASS; управляемые WG1→WG2, обычный stop,
stop при paused API, постоянный receipt и watcher retry PASS. Подписанные APK/IPK
собраны тем же ключом; установка обновлённого APK с проверкой подписи прошла.
Новая проверка: tests/wg-release-e2e.py. Повтор проверки на установленном APK
прошёл; обновление IPK на 24.10.8 установлено с сохранением настроек.
Перезагрузка QEMU с paused API: постоянный receipt сохранён, после возвращения
API watcher освободил слот; PASS. Публичная доставка проверяется отдельно.

Публичный выпуск0.1.1:16 файлов полностью скачаны по HTTPS, SHA256 совпали.
Серверный PR155/02d80ab выложен на оба чистых контроллера, ready4/standby0.
Public installer на24.10.8 заново установил клиент, LuCI и Xray из подписанного
feed без обхода TLS/подписей. На25.12 управляемый API намеренно подменён
локальным fixture, поэтому публичный installer там отдельно не заявляется;
подписанный APK и сценарии WireGuard проверены на установленном пакете.
