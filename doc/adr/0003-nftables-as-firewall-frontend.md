# 3. nftables as the Firewall Frontend

Date: 2025-07-14

## Status

Proposed

## Context

FEAT-0001 requires a firewall role that enforces a default-deny inbound policy, whitelists specific ports (SSH, Xray, Hysteria2, AmneziaWG), and applies a client-IP whitelist (AC-6, AC-7). The firewall ruleset must be idempotent: re-applying the same role must not produce `changed` tasks when the ruleset is already correct (AC-3), and changing a port variable must update only the relevant rule (AC-4).

The role must be testable via a Molecule/Docker scenario that asserts ruleset contents (AC-6), and must be operationally transparent enough that an operator can read the deployed ruleset with a single command to verify it manually.

Both Ubuntu 22.04 LTS and Debian 12 (bookworm) are supported targets. FEAT-0001 references both `nft list ruleset` and `ufw status verbose` as possible verification commands, indicating the choice between the two was not settled at feature authoring time.

## Decision

We adopt **nftables** (via `ansible.builtin.template` rendering an `/etc/nftables.conf` and the `nftables` systemd service) as the sole firewall frontend. The Ansible firewall role templates a complete nftables ruleset from variables, applies it with `nft -f`, and verifies correctness by asserting `nft list ruleset` output in the Molecule `verify.yml`. ufw is explicitly not installed or enabled.

**Alternatives rejected:**

- **ufw (Uncomplicated Firewall):** ufw is a frontend over iptables (nft-compat on modern kernels). Its design goal is simplicity for interactive use, not programmatic idempotency. `ufw allow <port>` is additive and not idempotent in the sense required here — repeated application accumulates duplicate rules unless explicitly checked. Achieving true idempotency with ufw requires either a full `ufw reset` before each apply (which causes a momentary default-deny gap, interrupting live connections) or complex per-rule existence checks. Additionally, ufw's rule introspection (`ufw status verbose`) does not emit structured output, making `verify.yml` assertions brittle. nftables' `nft list ruleset` emits a canonical, parseable format.

- **iptables (direct):** iptables is superseded by nftables in the Linux kernel (nf_tables subsystem) on all target OS versions. Ubuntu 22.04 and Debian 12 both ship nftables as the default and use `iptables-nft` as a compatibility shim. Writing roles against raw iptables chains couples the firewall role to a deprecated interface. The Ansible `ansible.builtin.iptables` module also has known idempotency edge cases with chain ordering.

- **firewalld:** firewalld adds a D-Bus daemon and zone abstraction layer that is well-suited to desktop Linux and RHEL-family servers but is not the default on Ubuntu or Debian, requires an additional package install, and its zone model is more complex than necessary for a single-interface VPS. The added daemon is operational surface area with no benefit for this single-interface use case.

**Reversibility:** Low-to-moderate. nftables rules are stored as a single templated file; migrating to a different frontend requires rewriting the template and the `verify.yml` assertions, but does not affect any other role. The decision is **moderately reversible** in isolation, but if future features build firewall assertions against `nft list ruleset` output format, those will also need updating.

## Consequences

- **Positive:** A single `/etc/nftables.conf` template, rendered from variables, makes the complete ruleset visible in one file. Idempotency is achieved by re-rendering the template and reloading only when the file content changes (Ansible `notify` on template task). No per-rule accumulation, no reset-and-reapply gap.
- **Positive:** `nft list ruleset` emits a canonical, human-readable, and grep-able format suitable for both operator verification and `verify.yml` assertions using `ansible.builtin.command` + `ansible.builtin.assert`.
- **Positive:** nftables is the kernel-native subsystem on both Ubuntu 22.04 and Debian 12; no compatibility shim is needed, and the package (`nftables`) is available in base APT repositories on both.
- **Negative:** nftables syntax (tables, chains, sets, rules) is more verbose than ufw's `ufw allow <port>` shorthand, increasing the complexity of the template for operators unfamiliar with nftables. The template must be well-commented.
- **Negative:** nftables reload (`systemctl reload nftables` or `nft -f`) replaces the entire ruleset atomically. If the template renders an invalid ruleset due to a variable error, the reload will fail and leave the previous ruleset active. This is safer than partial application but means template syntax errors surface only at apply time, not at lint time. The Molecule scenario must include a negative test with an intentionally invalid variable to verify the failure mode.
- **Operational note:** ufw must not be installed on target VPSes provisioned by this playbook; if a VPS image ships with ufw pre-enabled, the prerequisites role must explicitly disable and mask the `ufw` service before the firewall role runs to prevent ruleset conflicts.
