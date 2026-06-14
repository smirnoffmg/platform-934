# ansible/

Ansible provisioning for the censorship-resistant proxy stack.

## Variable file (`vars/main.yml`)

All tunable parameters are declared in `vars/main.yml`. **Variable renames here are a breaking change for TASK-0002 through TASK-0006** — every role template references these names directly.

| Variable                  | Protocol             | Placeholder convention          |
| ------------------------- | -------------------- | ------------------------------- |
| `xray_port`               | Xray (VLESS+REALITY) | `"PLACEHOLDER_XRAY_PORT"`       |
| `xray_uuid`               | Xray                 | `"PLACEHOLDER_XRAY_UUID"`       |
| `xray_server_name`        | Xray                 | `"PLACEHOLDER_SNI"`             |
| `hysteria2_port`          | Hysteria2            | `"PLACEHOLDER_HY2_PORT"`        |
| `hysteria2_obfs_password` | Hysteria2            | `"PLACEHOLDER_HY2_OBFS"`        |
| `awg_port`                | AmneziaWG            | `"PLACEHOLDER_AWG_PORT"`        |
| `awg_jc`                  | AmneziaWG            | `"PLACEHOLDER_AWG_JC"`          |
| `awg_jmin`                | AmneziaWG            | `"PLACEHOLDER_AWG_JMIN"`        |
| `awg_jmax`                | AmneziaWG            | `"PLACEHOLDER_AWG_JMAX"`        |
| `ssh_port`                | SSH                  | `22` (real default, non-secret) |
| `client_ip_whitelist`     | Firewall             | `[]` (real default, non-secret) |

All `PLACEHOLDER_*` values are overwritten at deploy time by the SOPS decrypt step (FEAT-0002). Port placeholder values are strings — Jinja2 templates must pipe through `| int` before using them as integers.

`group_vars/vps.yml` is intentionally empty. Ansible variable precedence places `group_vars` above `vars_files`, so any variable defined there would silently override `vars/main.yml`.

## Role execution order

Roles run in dependency order as declared in `playbook.yml`:

1. **prerequisites** — OS hardening, kernel tuning (BBR), fail2ban; no protocol variables consumed (TASK-0002)
2. **amneziawg** — DKMS kernel module, WireGuard interface config; consumes `awg_port`, `awg_jc`, `awg_jmin`, `awg_jmax` (TASK-0003)
3. **xray** — Xray-core install, VLESS+REALITY config template, systemd unit; consumes `xray_port`, `xray_uuid`, `xray_server_name` (TASK-0004)
4. **hysteria2** — sing-box install, Hysteria2 config template; consumes `hysteria2_port`, `hysteria2_obfs_password` (TASK-0005)
5. **firewall** — nftables ruleset; consumes all port variables and `client_ip_whitelist`; enforces that all ports are distinct and `awg_jmax >= awg_jmin` (TASK-0006)

## OS support

Supported targets: **Ubuntu 22.04 LTS**, **Debian 12**.

A fast-fail assertion in `playbook.yml` `pre_tasks` checks `ansible_distribution` and `ansible_distribution_version`/`ansible_distribution_major_version` before any role runs. Any other OS causes an immediate failure with a human-readable message.
