---
id: TASK-0014
status: todo
feature_id: FEAT-0005
---

## Description

The `firewall` role is updated to open port 80 unconditionally when `decoy_enabled` is true, and additionally open port 443 when `decoy_domain` is non-empty. When `decoy_enabled` is false (the default), firewall behaviour is identical to the TASK-0006 baseline and no new ports are opened. After this task, the ACME HTTP-01 challenge can complete and Caddy can serve HTTPS when a real domain is configured.

Done looks like:

- `roles/firewall/templates/nftables.conf.j2` (or equivalent ufw task) conditionally includes a rule to accept TCP on port 80 when `decoy_enabled | bool` is true.
- The same template conditionally includes a rule to accept TCP on port 443 when `decoy_enabled | bool` is true and `decoy_domain | length > 0`.
- When `decoy_enabled: false`, running the playbook produces the same firewall output as before this task, and the Molecule scenario for the firewall role still passes unchanged.
- The existing firewall Molecule scenario is extended with a second converge scenario that sets `decoy_enabled: true` and `decoy_domain: ""`, verifying port 80 appears in the ruleset and port 443 does not.
- Re-running with no variable changes produces `changed=0` for the firewall role in both `decoy_enabled: true` and `decoy_enabled: false` modes.

## Notes

- Depends on TASK-0006 (firewall role exists with its nftables template) and TASK-0009 (vars schema declares `decoy_enabled` and `decoy_domain`).
- The firewall role must not restart Xray, Hysteria2, or AmneziaWG when only firewall rules change — this constraint from TASK-0006 is unchanged.
- The `decoy_enabled` variable guards the firewall rule additions, not the role's presence in `playbook.yml`. The role always runs; the conditional is inside the template. This keeps the playbook role list simple.
- Port 443 rule: only needed when Caddy serves HTTPS (i.e., `decoy_domain` is set). When `decoy_domain` is empty, Caddy serves HTTP only on port 80 and no 443 rule is needed.
- Ensure the Molecule scenario for this task does not require Docker to actually listen on the port — just verify the rendered nftables config (or ufw status) contains the expected rule text.
