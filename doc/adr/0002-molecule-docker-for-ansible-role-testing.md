# 2. Molecule + Docker as the Ansible Role Testing Framework

Date: 2025-07-14

## Status

Proposed

## Context

FEAT-0001 requires that every Ansible role ships with automated tests, and that `make test` runs all of them. The test framework must be able to assert idempotency (AC-3), variable-driven config rendering (AC-5), and firewall rule correctness (AC-6) without requiring a live VPS. It must run in CI on every PR touching a role.

The testing boundary has a known hard limit: DKMS module compilation (AmneziaWG) and network-level firewall behavior require a real kernel and real NIC. The framework chosen must acknowledge this limit cleanly — it must make the covered/not-covered boundary explicit rather than silently skipping untestable assertions.

The framework must also integrate with the Ansible ecosystem directly (it runs actual `ansible-playbook` invocations, not mocked calls) so that the test exercises the same code path as production deployment.

## Decision

We adopt **Molecule** (with the **Docker driver**) as the test framework for all Ansible roles. Each role contains at least one Molecule scenario. Scenarios use Docker containers as the managed host, which allows `ansible-playbook` to run against a real Debian/Ubuntu image with systemd available (via `ghcr.io/geerlingguy/docker-*-ansible` or equivalent systemd-capable images). The idempotency check is the Molecule built-in (`idempotency` step), which re-runs the playbook and fails if any task reports `changed`. Assertions are written in a `verify.yml` playbook using `ansible.builtin.assert` and `ansible.builtin.command` to inspect rendered files and rule state.

Molecule scenarios explicitly do **not** assert AmneziaWG `lsmod` state (AC-1 partial, AC-8) or network-level whitelist enforcement (AC-7). These are documented as real-VPS-only in the FEAT-0001 testing matrix and are run manually before a feature is marked accepted.

**Alternatives rejected:**

- **`ansible-test` (Red Hat / Ansible Collections framework):** Designed for testing Ansible collections distributed on Ansible Galaxy, not for application-layer playbooks. It imposes a collections directory structure and requires content to be packaged as a collection. This overhead is not justified for a single-operator provisioning repository. Molecule has no such structural requirement.

- **Vagrant + VirtualBox/libvirt:** Provides a real kernel and init system, which would allow DKMS and network tests in CI. Rejected because: (a) Vagrant VMs take 2–5 minutes to boot, making CI latency unacceptable for per-PR runs; (b) nested virtualization is unavailable on most CI runners; (c) Docker containers with systemd cover the 80% case (service unit, template rendering, idempotency) at a fraction of the boot cost.

- **Plain pytest + testinfra (without Molecule):** Testinfra can assert file/service state inside a Docker container, but it does not drive `ansible-playbook` directly — it only inspects state after some out-of-band setup step. This breaks the integration between test and provisioner: a passing testinfra suite does not prove that the Ansible role produced the observed state. Molecule's `converge` → `idempotency` → `verify` pipeline keeps the provisioner as the unit under test.

- **No automated role tests (manual VPS only):** Ruled out by AC-11 and the FEAT-0001 definition of done. Without a fast feedback loop in CI, role regressions are only discovered on real-VPS runs, which are manually triggered and infrequent.

**Reversibility:** Moderate. Molecule scenarios are structured YAML + `verify.yml` playbooks. Migrating to a different framework would require rewriting the scenario scaffolding but would not change the underlying role tasks or templates. The decision is **moderately reversible** at the cost of rewriting test scaffolding.

## Consequences

- **Positive:** Molecule's built-in idempotency check (AC-3) requires zero additional test code — re-running the playbook and asserting `changed=0` is the default behavior of the `idempotency` step.
- **Positive:** Docker containers start in seconds, keeping `make test` fast enough to run on every PR without CI cost pressure.
- **Positive:** Using systemd-capable Docker images means `systemctl is-active` assertions in `verify.yml` reflect real service behavior, not mocked state.
- **Negative:** Docker containers share the host kernel; DKMS module compilation (`modprobe`, `lsmod`) cannot be tested. The test coverage gap for AmneziaWG (AC-1 partial, AC-8) is inherent to this choice and must be compensated by mandatory real-VPS runs before merge of any AmneziaWG role change.
- **Negative:** systemd inside Docker requires a privileged container or specific capability flags (`--cap-add SYS_ADMIN`, cgroup v2 configuration). CI runner configuration must explicitly support this; teams using rootless Docker or restrictive seccomp profiles will need workarounds.
- **Negative:** Molecule adds a Python dependency (`molecule`, `molecule-plugins[docker]`) to the developer workstation. The version of Molecule must be pinned to avoid breaking changes between Molecule 6.x releases. This pin must be maintained alongside the Ansible version pin.
- **Coverage boundary:** The table in FEAT-0001 (AC-1 partial, AC-2, AC-7, AC-8) documents which ACs are not coverable in Docker. Any AC added to FEAT-0001 that requires real kernel state must be flagged in the scenario's `README` as real-VPS-only and excluded from the Docker scenario's `verify.yml`.
