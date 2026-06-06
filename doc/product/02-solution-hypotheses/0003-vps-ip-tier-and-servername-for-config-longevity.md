---
id: SOL-0003
status: proposed
problem_hypothesis_id: PROB-0001
target_metric_id: MET-0003
secondary_metric_ids:
  - MET-0008
---
# VPS IP Tier and serverName Selection for Config Longevity

## Context

Config survival duration depends on three factors beyond protocol stealth:

**IP/ASN reputation (primary concern for Russia):** TSPU's 16 KB curtain targets connections to foreign datacenter IP ranges by ASN reputation, not just protocol signature. Hetzner, DigitalOcean, OVH, and the major cloud providers (AWS, GCP, Azure) have their entire ASN ranges effectively targeted — the same ranges Russians use to self-host private proxies. A REALITY config on a clean-IP provider in the same protocol and port configuration will survive significantly longer than on a flagged ASN, because the curtain and associated DPI scrutiny are triggered by IP reputation before any protocol handshake occurs.

**Port and SNI selection (primary concern for Russia):** A February 2026 analysis (Habr teardown) showed port 443 on Russia-facing servers experienced instant drops, while high random ports (47000+) passed ~80% of packets. The same analysis found empty SNI lifted the block in 100% of test cases. Port and SNI are therefore survival levers for Russia that are independent of protocol choice.

**serverName quality (primary concern for China):** REALITY borrows a real site's TLS 1.3 Server Hello. A poor serverName (a CDN-redirect domain, a previously-blocked decoy, a site with a short cert, or a domain in a different country/ASN than the VPS) weakens the REALITY active-probe response and may accelerate detection. The serverName should be a real TLS 1.3 + HTTP/2 capable site in the same ASN or geographic region as the VPS, with no redirect chains.

## Decision

We hypothesize that:

1. **Russia:** Deploying on a provider with a clean, non-flagged ASN (Finland, Germany, or Latvia, explicitly not Hetzner/DO/OVH) at a random high port (47000+) with a configurable SNI (including the ability to set empty SNI) will extend mean config survival duration to ≥14 days on the Russia path.

2. **China:** Selecting a serverName from a curated list of real TLS 1.3 + HTTP/2 sites in the same ASN/region as the VPS will extend mean config survival duration to ≥14 days on the China path.

The provisioner includes a pre-deploy ASN reputation check that warns (but does not block) when the target VPS IP is in a known-flagged range, and maintains a curated, tested serverName list with rotation instructions.

## Experiments

1. **IP tier comparison (Russia):** Deploy identical configs (same protocol, port, SNI) on a flagged ASN (Hetzner) and a clean-IP provider. Measure survival duration on the Russia path. Expected: flagged ASN config burned significantly faster.

2. **Port and SNI impact (Russia):** Deploy REALITY on port 443 vs. a random high port (47000+) on the same clean-IP provider. Compare survival duration. Repeat with empty SNI vs. a real serverName.

3. **serverName quality comparison (China):** Deploy REALITY with a same-ASN serverName vs. a geographically distant, CDN-backed serverName. Compare active-probe response quality and survival duration on the China path.

4. **ASN reputation check validation:** Run the provisioner's pre-deploy ASN check against a set of known-flagged (DO, Hetzner, AWS) and known-clean providers. Confirm true-positive rate ≥90% and false-positive rate ≤10%.

## Success criteria

- MET-0003: ≥14 days mean config survival on Russia path (clean-IP provider, high port) and China path (curated serverName).
- Clean-IP provider survival duration ≥2× flagged-ASN provider survival duration on Russia path.
- ASN reputation check identifies flagged ranges with ≥90% true-positive rate.

## Consequences

- **If confirmed:** Clean-IP provider selection and port/SNI configuration are documented as non-optional prerequisites, not optional hardening. The provisioner enforces the warning gate.
- **If Russia survival still short on clean IPs:** The 16 KB curtain is targeting these IPs by connection pattern rather than ASN — IP rotation and residential IPs become the next avenue.
- **If China serverName quality correlation confirmed:** The serverName curation list becomes a maintained artifact, updated as domains are collaterally blocked.
- **Ongoing risk:** Clean-IP provider reputation degrades as more users concentrate on them. The provisioner's provider tier list must be reviewed quarterly.
