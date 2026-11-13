# Security boundaries

## Credentials

Never put production credentials in issues, logs, screenshots, examples or
commits. The client does not embed an administrative API key. User access tokens,
refresh tokens, installation proof, subscription URLs and WireGuard private keys
are stored in `/etc/overwall` (directory 0700, files 0600). Runtime requests and
generated engine configuration live in `/var/run/overwall` with the same access
restrictions. WireGuard configuration in UCI is restricted to root.

Overwall control requests use a fixed HTTPS origin and never follow redirects.
Credentials are passed to curl through a private configuration file, not process
arguments. Source updates never receive Overwall credentials. Public status RPC
responses contain display names and state, not connection URIs or keys.

Subscription fetching pins a validated public IPv4 destination after resolution,
rejects local/service addresses and redirects, and limits duration and body size.
Only authenticated LuCI administrators can add sources or change routing. This
restriction is deliberately separate from the ability to read status.

## Network policy

The VPN applies to the selected network, not every interface on the router.
Router management remains reachable. A separate nftables table blocks direct
forwarding if the tunnel or its policy route disappears. An explicit disconnect
removes the protection and disables automatic connection. IPv6 is blocked for
the selected network until IPv6 tunneling is independently validated.

Account status failures are unknown state, not proof that a customer is unpaid.
Overwall quotas never revoke independent subscriptions. A profile imported from
another provider cannot authorize arbitrary system commands or listeners.

Root/admin access, a compromised router firmware, or hostile physical access is
outside this protection boundary. Another LAN device can observe its own
traffic and operate a separate proxy; the client is not a parental-control or
hostile-user network enforcement system.

## Reporting

Use the private security reporting facility of this repository when enabled.
If unavailable, use the official contact on https://overwall.online and send
only a description initially. Do not publish a working exploit with user data.

Before a public release: run the account isolation, replay/revocation, import,
RPC access-control, leak and package-content checks in the acceptance matrix.
