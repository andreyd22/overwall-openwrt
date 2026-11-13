# Overwall VPN for OpenWrt

A LuCI client for Overwall accounts, independent VLESS subscriptions and
WireGuard profiles. The UI and controller are open source; the Overwall server
and customer credentials are not part of this repository.

## Development status

Version 0.1.0 is an **open beta**. Back up router settings before installation.
Physical home-router acceptance is still pending; keep local access for recovery. See [the test matrix](docs/acceptance.md).

Supported package formats: OpenWrt 25.12 (`.apk`) and 24.10 (`.ipk`).
The controller is architecture independent and uses OpenWrt packages for Xray,
WireGuard, firewall4 and LuCI. Device compatibility still depends on those
dependencies, available flash/RAM and actual testing.

## Features

- Overwall device pairing using a one-time code and QR confirmation on the site.
- Multiple independent subscription URLs and VLESS/Base64/Xray JSON imports.
- WireGuard import by pasting or uploading a configuration.
- Independent sources do not require an Overwall account. Their links, private
  keys and configurations stay on the router and are never uploaded to Overwall.
- One active connection for an administrator-selected LAN or guest network.
- A firewall guard prevents automatic direct forwarding after tunnel failure.
  IPv6 forwarding from the selected network is blocked in this version.
- Overwall access checks distinguish VLESS quotas from WireGuard entitlement.

Imported Xray configurations contribute connection settings only. Provider
listeners, routing and system operations are not imported. WireGuard executable
hooks are rejected. This version supports one peer and a full IPv4 tunnel per
WireGuard profile.

## Build and test

The package definitions are in `packages/`. Add this repository as an OpenWrt
feed and install both package definitions alongside the LuCI feed. Build with
the SDK matching your OpenWrt release. Runtime engines come from the OpenWrt
repositories; do not copy arbitrary prebuilt engines into these packages.

For the local development lab, see [lab setup](docs/lab.md). The lab uses official
OpenWrt images with verified checksums, QEMU, a separate WAN and two LAN clients.
All fixture keys, disk images, captures and SDKs belong under ignored `lab/` or
`sdk/`, never in a commit.

```sh
python3 scripts/install-overlay.py   # disposable lab only; not a release installer
python3 tests/e2e.py                 # real TCP/UDP through the router
python3 scripts/build-packages.py    # SDK apk-tools plus deterministic IPK packaging
```

## Installation

See [the installation guide](docs/install-ru.md). Install only a signed release
with its matching public key and checksums. Do not disable TLS or package
signature verification. New WireGuard dependencies may require one router
reboot before netifd recognizes the protocol.

## Security

The public API address is not a secret. Individual device tokens authorize only
the account that signed in. Administrative credentials are never distributed.
See [security boundaries](SECURITY.md). Being root on the router grants access to
its saved VPN credentials, as with other router VPN clients.

License: Apache-2.0 for original client code. Xray, WireGuard, LuCI, uhttpd and
other dependencies retain their own licenses and are installed separately.

## Requirements and installation

Minimum: 256 MB RAM and 50 MB free persistent storage; 512 MB RAM recommended.
Use stable OpenWrt 25.12.x or 24.10.x with matching official repositories.
See [Russian installation guide](docs/install-ru.md) and
https://overwall.online/download#openwrt for the signed repository installer.
Dependencies are resolved automatically by apk/opkg; no manual engine installation.
