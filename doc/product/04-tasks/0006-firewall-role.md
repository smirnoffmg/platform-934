---
id: TASK-0006
status: todo
feature_id: FEAT-0001
---

## Description

An idempotent `firewall` Ansible role applies an nftables (or ufw) ruleset that enforces default-deny inbound with explicit allowances for SSH, the configured Xray port, the configured Hysteria2 port, and the configured AmneziaWG port, and restricts SSH access to IPs in `client_ip_whitelist`. After this task, `nft list ruleset` on the VPS matches the expected policy and a re-run produces `changed=0`.

Done looks like:

- `roles/firewall/templates/nftables.conf.j2` (or equivalent ufw task sequence) generates rules driven entirely by variables from `vars/main.yml`: `ssh_port`, `xray_port`, `hysteria2_port`, `awg_port`, and `client_ip_whitelist`.
- The rendered ruleset: sets default policy to drop for input chain; accepts established/related; accepts loopback; accepts SSH only from IPs in `client_ip_whitelist`; accepts Xray, Hysteria2, and AmneziaWG ports from any source.
- The firewall service (`nftables` or `ufw`) is enabled and started; rules persist across reboots.
- Re-running with no variable changes produces `changed=0`.
- Changing `xray_port` and re-running updates only the firewall rules; no service restart of Xray or Hysteria2 occurs from within this role.
- A Molecule scenario verifies: nft rules (or ufw status output) contain the expected port allowances (AC-6), `client_ip_whitelist` entries appear in SSH restrictions (AC-6), and idempotency (AC-3). AC-7 (network-level rejection from non-whitelisted IP) is documented as real-VPS only and excluded from Docker scenario.

## Notes

- Depends on TASK-0001 (vars schema, specifically all port variables and `client_ip_whitelist`).
- Prefer nftables over ufw for explicit rule control and scripted verification; ufw is acceptable if it simplifies Molecule verification. Pick one and document the choice in the role README.
- The `client_ip_whitelist` variable is a YAML list; the template must iterate it correctly. If the list is empty, SSH must still be accessible (fail-safe: do not lock out the operator).
- AC-7 (connection refused from non-whitelisted IP) requires a real NIC and cannot be tested in Docker. Document this gap explicitly in the Molecule scenario README and include a manual real-VPS test checklist.
- This role must not restart Xray, Hysteria2, or AmneziaWG — firewall rule changes do not require protocol service restarts.
