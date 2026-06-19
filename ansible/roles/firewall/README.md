# firewall role

Applies a default-deny nftables ruleset on the `input` chain with explicit
allowances for SSH, Xray, Hysteria2, and AmneziaWG.

## Technology choice: nftables (not ufw)

nftables is used because `nft list ruleset` (or, equivalently, the rendered
`/etc/nftables.conf`) is deterministic and machine-readable, which lets the
Molecule scenarios assert on exact rule text instead of parsing ufw's
human-readable prose output. This also matches the `nftables` package this
role's tasks/install.yml already installs and the `prerequisites` role's
package list.

## Variables consumed

All sourced from `ansible/vars/main.yml` (this role defines no defaults of
its own):

- `ssh_port`
- `xray_port`
- `hysteria2_port`
- `awg_port`
- `client_ip_whitelist`

## Fail-safe: empty `client_ip_whitelist`

If `client_ip_whitelist` is empty, SSH is permitted from any source rather
than blocked entirely — an empty list must never lock the operator out.
`client_ip_whitelist` entries should be unique; the template applies a
`unique` filter so accidental duplicates don't produce spurious `changed`
diffs on re-run.

`client_ip_whitelist` accepts IPv4 addresses only — the template uses `ip
saddr` (the IPv4 address family in nftables). An IPv6 entry would be
silently ignored. IPv6 support (`ip6 saddr` / `meta nfproto ipv6`) is a
follow-up, not in scope here (YAGNI).

## Protocol/port mapping

| Variable         | Protocol | Rationale                    |
| ---------------- | -------- | ---------------------------- |
| `ssh_port`       | TCP      | SSH                          |
| `xray_port`      | TCP      | VLESS+XTLS-Vision+REALITY    |
| `hysteria2_port` | UDP      | Hysteria2 runs over QUIC     |
| `awg_port`       | UDP      | AmneziaWG is WireGuard-based |

A reviewer changing a port variable must not accidentally swap `tcp dport`
and `udp dport` in `templates/nftables.conf.j2`.

## No service restarts

This role notifies only its own `Reload nftables` handler (`nft -f
/etc/nftables.conf`), never a restart of Xray, Hysteria2, or AmneziaWG.
Firewall rule changes do not require protocol service restarts. If a
reviewer sees a `notify:` call for `Restart xray`, `Restart hysteria2`, or
`Restart amneziawg` anywhere in this role, that is a bug.

## Maintenance obligation

If `awg_port` or `hysteria2_port`'s transport protocol ever changes (e.g., a
hypothetical Hysteria3 over TCP), update `templates/nftables.conf.j2`
accordingly and re-run Molecule.
