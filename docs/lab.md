# Isolated lab and measurements

Use official OpenWrt ext4 x86-64 QEMU images and verify SHA-256 against the
release's official `sha256sums`. The 25.12.6 lab runs QEMU TCG with two virtio
NICs and unique MAC addresses. LAN 172.30.77.0/24 is isolated from the host's
normal LAN; the router is .1. Two Docker clients obtain DHCP leases from it.
WAN uses QEMU user networking. Host management binds only 127.0.0.1:12222
(SSH) and 127.0.0.1:18080 (LuCI). Never expose the passwordless disposable lab.

The lab container needs NET_ADMIN, /dev/net/tun, QEMU, iproute2 and WireGuard.
A TAP/bridge joins the guest LAN to the dedicated Docker network. Do not mark
the Docker bridge `internal`: that drops forwarded traffic outside its subnet.
Store images, lab SSH/TLS keys and generated WireGuard fixtures in ignored
`lab/`, with secrets mode 600. Fixtures never use production accounts.

`tests/e2e.py` exercises TCP/UDP from both clients and the fail-closed guard.
It rotates the isolated WireGuard server key: regenerate account fixtures
before mixing it with `tests/account-e2e.py`.
`tests/account-fixture.cjs` uses the real backend pairing handler with an
isolated Valkey and fake account/entitlement providers. Trust its lab-only TLS
certificate in the guest only; do not disable TLS verification.
`tests/rpc-e2e.py` checks real LuCI RPC ACLs and asynchronous commands.
`tests/parser.uc` runs in the OpenWrt guest. `tests/ui.cjs` checks DOM behavior;
real browser screenshots and responsive checks are separate evidence.

Memory benchmark: start `tests/load-origin.py` in the WAN fixture container,
then `tests/memory-load.py` from the host. Two clients each run 8 concurrent
TCP downloads for 60 seconds per protocol. Samples read `/proc/meminfo` and
process VmRSS on the guest. Total used is MemTotal - MemAvailable; process RSS
must not be added to that total. WireGuard kernel memory is included in the
system total. Do not report QEMU's host memory as router RAM. The isolated
VLESS test endpoint is unencrypted; TLS/Reality and additional router services
can increase actual consumption. This is a memory workload, not a hardware
throughput certification. Results belong in ignored `lab/` and the public
acceptance summary must state the environment and limits.

The 24.10.8 package-install guest uses 256 MB RAM, a separate image and
management port 12223 inside the lab container. Its official repositories
install all runtime dependencies automatically; the custom feed uses usign.
The 25.12 feed uses signed APK packages and a signed ADB index. Never use
`--allow-untrusted` or forced dependencies to install release packages.
