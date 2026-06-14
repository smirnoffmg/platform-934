# 1. Ansible as the VPS Provisioning Tool

Date: 2025-07-14

## Status

Proposed

## Context

FEAT-0001 requires that a fresh VPS running Ubuntu 22.04 LTS or Debian 12 can be brought to a fully operational proxy stack — Xray (VLESS+XTLS-Vision+REALITY), Hysteria2, AmneziaWG (DKMS), and a hardened firewall — from a single command (`make deploy`) in ≤15 minutes. The provisioning tool must be idempotent: re-running it on an already-configured server with one changed variable must converge to the desired state, restarting only the affected service and leaving others untouched. This is not a convenience property; unnecessary service restarts create a detectable liveness gap that consumes rotation budget (SOL-0006).

The tool must also be operable from a workstation with a minimal install footprint (AC-9 requires only `ansible`, `sops`, and `age` as prerequisites) and must compose cleanly with secret injection (FEAT-0002) and post-deploy verification (FEAT-0003) inside a single `Makefile` pipeline.

## Decision

We adopt **Ansible** (≥ 2.15) as the sole provisioning tool. The playbook is structured as discrete roles — one per logical component (prerequisites, amneziawg, xray, hysteria2, firewall) — connected by a site-level playbook. All protocol parameters are defined in a `vars/` file; templated config files are rendered by Jinja2 templates inside each role. Service restarts are triggered exclusively through Ansible handlers notified by the tasks that change the relevant config or binary, ensuring that a single-variable change restarts at most the one service whose config depends on that variable (AC-4).

**Alternatives rejected:**

- **Shell scripts (bash/POSIX):** Offer no built-in idempotency primitives. Every operation must manually check current state before acting, leading to fragile ad-hoc conditionals. Achieving AC-3 and AC-4 with shell scripts would require reimplementing most of what Ansible provides, with higher maintenance cost and no structured test harness.

- **Terraform + cloud-init:** Terraform's strength is lifecycle management of cloud resources (VMs, DNS, networking). Cloud-init runs only on first boot and is not re-runnable for config updates. This combination handles provisioning of the VPS itself well but has no story for post-provision configuration convergence (port rotation, variable changes), which is the primary operational loop for this system. Using both Terraform and Ansible would add a second tool with no net gain for this scope.

- **Puppet / Chef / Salt:** Mature idempotent configuration management tools, but all require a persistent agent or master process on the target, adding operational surface area. Ansible's agentless SSH model matches the single-operator, ephemeral-VPS context better. The operator workstation footprint is also simpler (no server-side daemon to provision before provisioning).

- **Docker / container image push:** Not applicable. The target is a bare VPS running kernel modules (DKMS), raw systemd services, and nftables rules — none of which fit inside a container image deployment model.

**Reversibility:** High coupling. All subsequent infrastructure features (FEAT-0002, FEAT-0003, and any future provisioning features) build against Ansible role and variable conventions established here. Migrating to a different tool would require rewriting all roles and adapting the `Makefile` pipeline. This decision is **difficult to reverse** once multiple features are implemented against it.

## Consequences

- **Positive:** Ansible's built-in idempotency primitives (module state assertions, handlers, `changed_when`) make AC-3 and AC-4 achievable without custom state-tracking logic. The `ansible-playbook --check --diff` mode provides AC-5 verification with no additional tooling.
- **Positive:** Agentless SSH operation means no server-side daemon to bootstrap; the only prerequisite on the VPS is Python 3, which Ubuntu 22.04 and Debian 12 both ship by default.
- **Positive:** Role decomposition provides a natural boundary for Molecule test scenarios (ADR-0002), keeping each role independently testable.
- **Negative:** Ansible requires Python on the control node and the managed host. Python version mismatches between the operator workstation and the target OS can cause subtle failures; this must be documented in onboarding.
- **Negative:** Ansible's YAML DSL is verbose for complex conditional logic (e.g., the AmneziaWG DKMS build sequencing). Tasks that require shell fallback (`ansible.builtin.shell`) undermine idempotency and must be guarded with explicit `creates:` or `changed_when:` conditions — a pattern reviewers must actively enforce.
- **Negative:** Handler scoping in Ansible is playbook-global by default. Incorrectly scoped handlers can cause a restart to be silently skipped if notified from a role that is not reached, or triggered spuriously if another role re-uses the same handler name. AC-4's correctness depends on reviewers catching this class of bug; it is not statically detectable.
- **Maintenance:** Ansible 2.15 introduces collection-namespaced modules (`ansible.builtin.*`). Any role using short module names will produce deprecation warnings and may break on future Ansible versions; all roles must use fully qualified module names.
