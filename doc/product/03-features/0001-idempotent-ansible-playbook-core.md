---
id: FEAT-0001
status: proposed
solution_hypothesis_id: SOL-0006
architectural_review_status: cleared
---

# Idempotent Ansible Playbook Core

## Context

SOL-0006 establishes that IP rotation is only a viable operational response to a blocked config if a fresh VPS can reach a fully working state from a single command. The underlying mechanism is an Ansible playbook that installs and configures every component of the proxy stack — Xray (VLESS+XTLS-Vision+REALITY), Hysteria2, AmneziaWG (via DKMS), and the firewall ruleset — in one unattended run.

Idempotency is not a quality-of-life property here; it is a correctness requirement. Re-running `make deploy` on an already-configured server to apply a variable change (e.g., rotating a port or SNI) must not restart services that were not changed, because unnecessary restarts produce a detectable liveness gap and waste the rotation budget. The playbook must converge to the desired state without side effects on already-correct components.

This feature covers the playbook structure, role decomposition, templated configuration files, and the `make deploy` entry point. Secret injection and post-deploy verification are handled in FEAT-0002 and FEAT-0003 respectively.

## Decision

**In scope:**

- An Ansible playbook with idempotent roles covering: system prerequisites (APT packages, kernel headers), AmneziaWG DKMS module build and installation, Xray service unit with VLESS+XTLS-Vision+REALITY config template, Hysteria2 service unit with config template, nftables/ufw firewall ruleset, and client-IP whitelist application.
- All protocol parameters (port, UUID, serverName, AmneziaWG `Jc`/`Jmin`/`Jmax`, Hysteria2 obfuscation password) are Ansible variables defined in a single `vars/` file, making rotation a variable change + re-apply.
- A `Makefile` target `make deploy` that: (1) invokes SOPS decrypt (FEAT-0002), (2) runs `ansible-playbook`, (3) triggers the connectivity check (FEAT-0003). Exit code 0 only when all three stages succeed.
- Playbook is tested against Ubuntu 22.04 LTS and Debian 12 (bookworm) as supported target OS images.
- AmneziaWG DKMS module must survive a VPS reboot (the DKMS hook must re-trigger on kernel upgrade).
- Each Ansible role ships with a Molecule scenario (Docker driver) covering the ACs testable in a container. Authoring the scenario is part of the role's definition of done — a role without a passing Molecule scenario is not considered complete.

**Out of scope:**

- Multi-user or multi-tenant provisioning. The playbook assumes a single operator SSH key and a single client-IP whitelist. Any extension to multi-user is a new feature and invalidates the whitelisting strategy.
- Provisioning the VPS itself (VM creation, DNS record). The playbook assumes a running VPS reachable by SSH on port 22. Cloud API integration is out of scope.
- Windows or macOS VPS targets. Linux only.
- Configuration of monitoring agents or log shippers on the VPS. Observability of the VPS host is out of scope for this feature.
- Rollback automation. If the playbook fails mid-run, the operator re-runs `make deploy`. Automatic rollback to the previous state is not provided.

## Testing

Molecule (Docker driver) is the primary automated test mechanism. It covers roughly half the ACs; the remainder require a real VPS with a real kernel and real network path.

| AC                                          | Molecule/Docker                                         | Real VPS required                     | Notes                                                                       |
| ------------------------------------------- | ------------------------------------------------------- | ------------------------------------- | --------------------------------------------------------------------------- |
| AC-3 (idempotency — zero changed)           | ✓ built-in Molecule idempotency check                   |                                       |                                                                             |
| AC-4 (idempotency — variable rotation)      | ✓ via Molecule scenario with variable override          |                                       |                                                                             |
| AC-5 (templated configs reflect variables)  | ✓ assert file contents in verify step                   |                                       |                                                                             |
| AC-6 (firewall default deny)                | ✓ assert nft/ufw rules in verify step                   |                                       |                                                                             |
| AC-1 (services active after cold deploy)    | partial — `systemctl is-active xray/hysteria2` testable | ✓ `lsmod amneziawg` needs real kernel | DKMS requires real kernel; Docker scenario omits AmneziaWG module assertion |
| AC-8 (AmneziaWG survives reboot)            | —                                                       | ✓                                     | Cannot simulate kernel module persistence in Docker                         |
| AC-2 (cold deploy time ≤ 15 min)            | —                                                       | ✓                                     | Docker I/O profile does not reflect real VPS timing                         |
| AC-7 (client-IP whitelist at network level) | —                                                       | ✓                                     | Requires real NIC and network isolation                                     |
| AC-9 (fresh-workstation reproducibility)    | ✓ run in CI with only ansible/sops/age installed        |                                       |                                                                             |
| AC-10 (Makefile exit code coupling)         | ✓                                                       |                                       |                                                                             |

Real-VPS tests (AC-2, AC-7, AC-8, and AmneziaWG portion of AC-1) are run manually before the feature is marked `accepted`, and on a cadence aligned with upstream Xray/AmneziaWG releases. They are not gated in CI due to cost.

`make test` runs all Molecule scenarios. It is a required pass before any PR touching an Ansible role is merged.

## Acceptance criteria

- **AC-1 (Cold deploy installs all services):** After `make deploy` on a fresh Ubuntu 22.04 or Debian 12 VPS with no prior Ansible state, `systemctl is-active xray`, `systemctl is-active hysteria2`, and `lsmod | grep amneziawg` all return success (exit code 0).
- **AC-2 (Cold deploy time):** Wall-clock time from `make deploy` invocation to the post-deploy connectivity check passing is ≤ 15 minutes (900 seconds) at the median across 3 runs on each of: one clean-IP Finland/Germany/Latvia provider, one Asia-Pacific CN2 GIA provider, one generic European provider. (Measurement method: CI timer wrapping the `make deploy` call; connectivity check defined in FEAT-0003.)
- **AC-3 (Idempotency — zero changed tasks):** Running `make deploy` a second time on a server that is already in the desired state produces an Ansible summary with `changed=0` and `failed=0`. No services are restarted during the second run.
- **AC-4 (Idempotency — variable rotation):** Changing exactly one variable (e.g., the Xray port) in `vars/` and re-running `make deploy` results in: only the tasks that depend on that variable reporting `changed`, Xray restarting exactly once, Hysteria2 and AmneziaWG not restarting.
- **AC-5 (Templated configs reflect variables):** After deployment, the deployed Xray config file on the VPS contains the exact port, UUID, and serverName values specified in `vars/`. The same holds for Hysteria2 and AmneziaWG parameters. Verified by `ansible-playbook --check` diff output matching the variable values.
- **AC-6 (Firewall — default deny):** After deployment, `nft list ruleset` (or `ufw status verbose`) on the VPS shows that all inbound ports are denied by default except: SSH (22 or operator-configured port), the configured Xray port, the configured Hysteria2 port, and the configured AmneziaWG port.
- **AC-7 (Client-IP whitelist applied):** SSH access to the VPS from an IP not in the configured `client_ip_whitelist` variable is rejected at the firewall level (connection refused or timed out). SSH from a whitelisted IP succeeds.
- **AC-8 (AmneziaWG survives reboot):** After a VPS reboot (`shutdown -r now`), `lsmod | grep amneziawg` returns exit code 0 within 60 seconds of the SSH port becoming reachable — without any manual intervention or re-running `make deploy`.
- **AC-9 (Fresh-workstation reproducibility):** On a workstation with only `ansible` (≥ 2.15), `sops`, and `age` installed, cloning the repository and running `make deploy` (with the age private key provided via `AGE_SECRET_KEY` environment variable or `~/.config/sops/age/keys.txt`) succeeds without any additional manual steps.
- **AC-10 (Makefile entry point):** `make deploy` exits with code 0 if and only if all three stages — SOPS decrypt, `ansible-playbook`, and the connectivity check — succeed. Any stage failure causes `make deploy` to exit non-zero and print a human-readable error indicating which stage failed.
- **AC-11 (Molecule scenarios pass):** `make test` runs all Molecule scenarios and exits 0. Each role has at least one scenario. The output identifies which role each scenario covers and which ACs it exercises.

## Consequences

- **Maintenance cost:** The playbook must be kept in sync with upstream package names and service unit formats for Xray, Hysteria2, and AmneziaWG. Upstream releases that change binary paths or systemd unit names will break the playbook silently until tested.
- **DKMS build time:** AmneziaWG DKMS compilation is the single most likely cause of exceeding the 15-minute convergence ceiling. If kernel headers are large or the provider's I/O is slow, the build alone may take 5–8 minutes. This must be profiled; if it consistently exceeds budget, pre-built DKMS packages or a kernel module cache must be introduced as a follow-up.
- **OS version drift:** Ubuntu 22.04 LTS reaches end-of-life April 2027; Debian 12 reaches EOL ~2026. Adding Ubuntu 24.04 and Debian 13 as supported targets is a follow-up task, not in scope here.
- **No rollback:** A failed mid-run deploy leaves the VPS in an unknown partial state. Operators must be aware that a second `make deploy` is always the recovery path, and must not assume a partial run produces a safe or usable configuration.
- **Breaking change risk on rotation:** AC-4 requires that only changed-variable-dependent tasks report `changed`. This demands careful use of Ansible handlers and `notify` rather than `always` restarts. Reviewers should verify that handler scoping does not cause silent no-restarts when it should restart (inverse failure mode).
- **Real-VPS test gap:** AmneziaWG DKMS (AC-1/AC-8), timing (AC-2), and network-level whitelist (AC-7) cannot be verified in CI. Regressions in these ACs are only caught by manual real-VPS runs. Any change to the AmneziaWG role or firewall role must trigger a manual real-VPS test before merge.
