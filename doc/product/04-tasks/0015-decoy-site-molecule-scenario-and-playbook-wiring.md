---
id: TASK-0015
status: todo
feature_id: FEAT-0005
---

## Description

A Molecule scenario for the `decoy_site` role (Docker driver, HTTP-only mode) verifies that Caddy is installed, active, and serves the correct content. `playbook.yml` is updated to include `decoy_site` as the last role in the execution order. `make test` discovers and runs the new scenario alongside existing role scenarios. After this task, AC-10 and AC-11 are covered in CI without a real VPS.

Done looks like:

- `roles/decoy_site/molecule/default/molecule.yml` configures a Docker scenario (same driver pattern as other roles).
- `roles/decoy_site/molecule/default/converge.yml` sets `decoy_domain: ""` and `decoy_enabled: true`, applies the `decoy_site` role (and the `firewall` role if needed to open port 80 in the container).
- `roles/decoy_site/molecule/default/verify.yml` asserts:
  - `caddy` binary is present at the expected path.
  - `systemctl is-active caddy` exits 0.
  - `curl -s -o /dev/null -w "%{http_code}" http://localhost:80` returns `200`.
  - The response body of `curl -s http://localhost:80` contains the value of `decoy_site_title` (default `"Software Solutions"`).
- An idempotency check (second `ansible-playbook` run) produces `changed=0` for the `decoy_site` role (AC-11).
- `playbook.yml` lists `decoy_site` as the final role after `firewall`, conditionally included when `decoy_enabled` is true (via `when:` on the role entry or a conditional import).
- `make test` (TASK-0008) is updated (or naturally discovers) the new scenario and runs it; the overall `make test` exit code remains 0 when the scenario passes.

## Notes

- Depends on TASK-0013 (decoy_site role tasks and templates), TASK-0014 (firewall role updated for decoy ports), TASK-0008 (make test wiring exists).
- ACME cert issuance is explicitly out of scope for Molecule — only HTTP-only mode is tested. Document in the scenario README: "ACME/HTTPS path requires a real domain and real VPS; see the manual real-VPS test checklist."
- systemd in Docker requires the container to run with `privileged: true` and a systemd-capable base image (same pattern used in other role scenarios). Follow the same approach as the existing role scenarios for consistency.
- The `playbook.yml` change (adding `decoy_site` last) must be backward-compatible: existing operators who do not set `decoy_enabled: true` see no behavioural change. The role must be fully skipped, not just a no-op.
- If `make test` discovers scenarios by path convention (e.g., `roles/*/molecule/default/`), no change to the Makefile is needed; the new scenario is found automatically. Verify this in the task implementation.
