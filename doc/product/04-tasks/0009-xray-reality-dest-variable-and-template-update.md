---
id: TASK-0009
status: todo
feature_id: FEAT-0005
---

## Description

`vars/main.yml` declares a new `xray_reality_dest` variable and the Xray config template references it instead of any hardcoded or implicitly derived destination. After this task, the REALITY `dest` field in the Xray config is fully driven by a variable, and operators who configure a local decoy site can point it at `127.0.0.1:443` without touching the template.

Done looks like:

- `vars/main.yml` contains `xray_reality_dest: "{{ xray_server_name }}:443"` with an inline comment explaining: default forwards REALITY probes to the external `xray_server_name` host; set to `"127.0.0.1:443"` when a local `decoy_site` with ACME is configured.
- `vars/main.yml` also contains `decoy_domain: ""` (empty string default) and `decoy_enabled: false` with inline comments.
- `roles/xray/templates/config.json.j2` uses `{{ xray_reality_dest }}` for the REALITY `dest` field — no hardcoded hostname or derived expression.
- A Molecule verify step confirms the rendered `config.json` on the test host contains the value of `xray_reality_dest` as configured in the scenario vars.
- Re-running with no variable changes produces `changed=0` for the xray role.

## Notes

- This is an addendum to TASK-0001's schema contract; it is a **breaking change** for any implementation of TASK-0004 already in progress. Merge this before or alongside TASK-0004; do not merge TASK-0004 without this variable present.
- `decoy_domain` and `decoy_enabled` are declared here so TASK-0013 (decoy_site role) and TASK-0014 (firewall update) have a stable variable interface to depend on.
- The default `"{{ xray_server_name }}:443"` preserves backward compatibility: existing deployments that do not set `xray_reality_dest` explicitly behave identically to before.
- Do not change any other variable names in `vars/main.yml`; this task's scope is additive only.
- The Molecule scenario for this task can be the existing xray role scenario extended with a `vars:` override for `xray_reality_dest`.
