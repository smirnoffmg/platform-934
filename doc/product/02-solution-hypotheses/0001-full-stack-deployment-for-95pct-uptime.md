---
id: SOL-0001
status: proposed
metric_ids:
  - MET-0001
  - MET-0002
  - MET-0003
---

# Full-Stack Deployment for ≥95% User-Experienced Uptime

## Context

No single protocol or operational practice produces reliable uptime in isolation. A user with the best protocol but no monitoring sits in silent downtime after a burn event. A user with fast detection but no fallback loses connectivity when the primary port is blocked. A user with fast rotation but dirty IPs burns configs every 48 hours and rotates continuously.

Uptime is a function of four interacting variables: how long configs survive before being burned, how quickly a burn is detected, how quickly rotation restores connectivity, and whether a fallback protocol provides coverage during the detection-to-rotation interval. The theoretical uptime ceiling is `survival_duration / (survival_duration + detection_latency + rotation_time)`. At the target thresholds from the component metrics — 14-day survival (MET-0003), 2-minute detection (MET-0004), 5-minute rotation (MET-0005) — this yields >99.9% theoretical uptime. The gap between theoretical and actual is absorbed by provider outages and whitelist-mode regional shutdowns, which are accepted as unresolvable within scope.

Russia is the primary target. TSPU's most effective tool is not protocol blocking but infrastructure targeting: the 16 KB curtain freezes TCP connections to flagged foreign datacenter IP ranges regardless of what protocol runs inside them, and the whitelist-mode regional shutdowns (averaging 2,000/month as of Dec 2025) reduce reachable destinations to ~57 state-approved sites. These require a UDP-path fallback and clean non-flagged IP selection as structural requirements, not optional hardening. China is a secondary target, where the threat model is different (active probing, entropy classification) and the primary mitigation is REALITY's transparent forwarding.

## Decision

We hypothesize that deploying the complete stack — VLESS+XTLS-Vision+REALITY as primary transport on a clean-IP VPS at a random high port, AmneziaWG (UDP) as the primary Russia fallback, Hysteria2 as the throughput and tertiary fallback, an Ansible provisioner with SOPS-encrypted secrets, a client-side polling daemon for burn detection, and a clean-IP VPS at a non-flagged Russian-accessible provider — as an integrated system will achieve ≥95% user-experienced uptime over any rolling 30-day window on the Russia path. China uptime is measured as a secondary outcome.

## Experiments

1. **90-day continuous observation (Russia primary):** Deploy on a Russia-appropriate clean-IP provider and run the MET-0001 polling daemon from a Rostelecom or Megafon connection continuously. Record uptime per 30-day window alongside all component metrics to attribute any failures to their root cause.

2. **Failure mode attribution:** For each downtime event, classify cause: burn not yet detected, rotation in progress, all protocols blocked simultaneously, provider outage, or whitelist-mode shutdown.

3. **Stress rotation cycle:** Artificially burn configs on a 3-day cadence for 30 days. Confirm automated detection and rotation keeps MET-0001 above 95% on the Russia path.

4. **China secondary observation:** Run the same polling daemon from a China-routed vantage in parallel. Report China uptime as secondary outcome; failures on the China path do not invalidate the hypothesis.

## Success criteria

- MET-0001: ≥95% uptime on Russia path over each 30-day window in the 90-day observation period.
- No single root cause accounts for more than 50% of total downtime across the observation period.

## Consequences

- **If confirmed:** The integrated stack as deployed is the canonical configuration for the Russia target. China outcomes inform whether additional China-specific tuning is warranted.
- **If refuted due to burn frequency:** Config survival or protocol stealth on the Russia path is the bottleneck — revisit provider and port/SNI selection.
- **If refuted due to recovery time:** Detection latency or rotation time is the bottleneck — reduce polling interval or investigate rotation step timing.
- **If refuted due to whitelist-mode shutdowns:** Accepted. A domestic relay hop is the only mitigation and is out of scope.
