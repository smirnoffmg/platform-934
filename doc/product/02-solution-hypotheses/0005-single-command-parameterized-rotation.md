---
id: SOL-0005
status: accepted
metric_ids:
  - MET-0005
  - MET-0001
---

# Single-Command Parameterized Rotation

## Context

Rotation is only a viable recovery strategy if it is cheap enough to use routinely. Without automation, rotating a self-hosted proxy involves provisioning or reconfiguring a VPS, installing dependencies, generating new keys, updating configs, applying firewall rules, updating the client, and testing — 1–3 hours of focused attention. At that cost, users tolerate a burned config for days rather than rotate, eliminating the structural advantage of a self-hosted single-user setup.

For Russia specifically, the rotation levers that matter most are port and SNI. A February 2026 analysis showed that moving from port 443 to a random high port (47000+) restored connectivity in ~80% of TSPU-blocked cases, and setting an empty SNI restored it in 100% of tested cases. These are cheap, low-risk rotations that should complete in under a minute of reconfiguration time — the bottleneck is applying the change and verifying it, not generating a new config.

For a full IP rotation (new VPS), the bottleneck is VPS provisioning API latency, package installation, and DNS propagation. Pre-baked machine images or low-TTL DNS entries can reduce this, but a 20-minute ceiling is achievable without them on most providers.

Rotation is also the mechanism by which the provisioner's templated config structure proves its value: all protocol parameters (port, UUID, keys, serverName, AmneziaWG junk params) are variables, not hardcoded. `make rotate` changes variables and re-applies — the same playbook that does a fresh deploy does a rotation, just with different inputs.

## Decision

We hypothesize that a `make rotate` target in the provisioner, which changes port + serverName + regenerates keys, applies the Ansible role idempotently, and runs the post-rotate connectivity check, will complete port+SNI rotation in ≤5 minutes on a live server. The target must not succeed until the connectivity check passes.

For full IP rotation (new VPS), the same `make rotate` target with a `new_vps=true` flag provisions a fresh server and completes within ≤20 minutes.

## Experiments

1. **Port+SNI rotation timing:** Run `make rotate` 5 times consecutively on a live VPS (each to a different port/SNI pair). Record wall-clock time from invocation to connectivity check passing. Report median and p95.

2. **Full IP rotation timing:** Provision a fresh VPS via the provisioner's new-VPS rotation path. Measure wall-clock time from invocation to connectivity check passing on the new IP. Repeat 3 times; report median.

3. **Rotation idempotency:** If `make rotate` is interrupted mid-run and re-run, confirm it converges to a working state without manual cleanup.

4. **Client config atomicity:** Confirm that after rotation the old config no longer connects and the new config connects on the first attempt, with no intermediate state where neither works.

5. **Russia-specific rotation:** Rotate from port 443 to a random high port with empty SNI on a Rostelecom test path. Confirm the rotated config passes the connectivity check within the 5-minute threshold.

## Success criteria

- MET-0005: Median port+SNI rotation time ≤5 minutes; full IP rotation ≤20 minutes across 5 and 3 runs respectively.
- Client config atomicity: zero attempts required with old config after rotation; new config connects on first attempt.
- Interrupted rotation: re-running `make rotate` after mid-run failure converges correctly in 100% of 5 test cases.

## Consequences

- **If confirmed:** `make rotate` becomes the documented first response to any detected burn or suspected block, usable as a routine operation rather than an emergency procedure.
- **If port+SNI rotation exceeds 5 minutes:** Profile the slow step — likely Ansible SSH connection setup, service restart, or connectivity check timeout — and optimize that step specifically.
- **If full IP rotation exceeds 20 minutes:** Investigate pre-baked images at target providers to eliminate package installation time.
- **Ongoing concern:** Rotation generates a new config on the server before the client has the new config. There is a brief window where no valid config exists on the client. The connectivity check in `make rotate` must fail gracefully and retry, not leave the user stranded.
