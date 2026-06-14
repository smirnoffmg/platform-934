---
id: SOL-0006
status: accepted
metric_ids:
  - MET-0006
  - MET-0005
  - MET-0003
  - MET-0004
---

# Idempotent Ansible Provisioner with SOPS-Encrypted Secrets

## Context

A censorship-resistant stack that cannot be reliably reproduced from scratch is fragile. If the user's VPS is seized, provider-banned, or simply has its IP flagged beyond recovery, the ability to stand up a new instance in minutes — with all protocols, firewall rules, and secrets in place — is the operational foundation of the rotation strategy.

Without a provisioner, fresh-VPS setup requires 1–3 hours of manual configuration. With a provisioner, it is a single command. The difference is not convenience — it is whether IP rotation is a viable response to a blocked config or an impractical one.

Key requirements for the Russia target: the provisioner must support clean-IP provider selection guidance, high-port configuration by default, and AmneziaWG kernel module installation alongside Xray and Hysteria2 service units. The provisioner must also not store secrets (UUIDs, keys, PSKs) in plaintext in the repository or on the VPS filesystem.

## Decision

We hypothesize that an Ansible-based provisioner with the following properties will bring a fresh VPS to a fully operational state in ≤15 minutes:

- **Idempotent:** Re-running `make deploy` on an already-configured server reports zero changed tasks and does not restart services unnecessarily.
- **Secret management:** Private keys and UUIDs are generated once, stored SOPS+age encrypted in the repository, and injected at provision time. No plaintext secrets at rest.
- **Templated configs:** All protocol parameters (port, UUID, serverName, AmneziaWG `Jc`/`Jmin`/`Jmax`) are Ansible variables. Rotation changes variables and re-applies the same playbook.
- **Post-deploy verification:** `make deploy` does not succeed until an automated connectivity check (>1 MB transfer through REALITY) passes.
- **Provider guidance:** The provisioner documents provider tiers by region (Russia: clean-IP Finland/Germany/Latvia providers, not Hetzner/DO/OVH; China: CN2 GIA Asia-Pacific) and runs a pre-deploy ASN reputation check.

## Experiments

1. **Cold deploy timing:** Provision a fresh VPS at each of three target providers: one Russia-appropriate clean-IP provider, one Asia-Pacific CN2 GIA provider, one generic European baseline. Run `make deploy` from a clean workstation. Measure wall-clock time from invocation to connectivity check passing. Repeat 3 times each; report median.

2. **Idempotency check:** Run `make deploy` twice in sequence on the same server. Confirm the second run reports zero changed tasks and does not restart any services.

3. **Secret hygiene audit:** After deployment, confirm no plaintext secrets exist in the VPS filesystem (outside running process memory), the Ansible working directory, or the repository checkout. SOPS decrypt must require the age key.

4. **Fresh-workstation reproducibility:** Clone the repository on a workstation with only `ansible`, `sops`, and `age` installed. Run `make deploy`. Confirm it succeeds without additional manual steps beyond providing the age private key.

5. **AmneziaWG kernel module install:** Confirm DKMS-based AmneziaWG kernel module installs correctly on first run and survives a VPS reboot.

## Success criteria

- MET-0006: Median cold-deploy time ≤15 minutes across all three tested providers.
- Second `make deploy` run: zero changed Ansible tasks.
- Zero plaintext secrets at rest after deployment (verified by secret hygiene audit).
- Fresh-workstation reproduction succeeds in 1 attempt with no manual intervention beyond providing the age key.

## Consequences

- **If confirmed:** The provisioner becomes the canonical and only supported deployment method. Manual server configuration is explicitly unsupported.
- **If deploy time exceeds 15 minutes:** Profile the slow step — likely package installation or AmneziaWG DKMS build — and cache or pre-bake that step.
- **If secret hygiene fails:** The provisioner is a security liability. A failed audit blocks the hypothesis from being accepted until resolved.
- **Ongoing concern:** VPS provider IP reputation changes faster than any static list. The pre-deploy ASN check warns but cannot guarantee a clean IP. The user must verify connectivity after every fresh deploy before relying on it.
- **Out of scope:** Multi-user provisioning. The provisioner is explicitly single-user; any change to that assumption invalidates the client-IP whitelisting strategy.
