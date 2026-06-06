---
id: SOL-0007
status: proposed
problem_hypothesis_id: PROB-0001
target_metric_id: MET-0007
secondary_metric_ids:
  - MET-0008
  - MET-0003
---
# VLESS + XTLS-Vision + REALITY as Primary Transport

## Context

Most modern proxy protocols fail against one of two detection mechanisms:

**Passive classification (GFW, China primary):** ML-based entropy and popcount heuristics flag "fully encrypted" traffic. This has rendered Trojan (~90% detected as of Aug 2025), VMess (~80% as of Sept 2025), and plain Shadowsocks effectively dead on China paths.

**Active probing (GFW, China primary):** After passive classification flags a connection, the GFW replays captured handshakes against the server to test if it responds like a real TLS site. Servers that respond differently from a legitimate HTTPS site are blocked.

For Russia, TSPU's primary mechanism is not protocol detection but IP/connection reputation and the 16 KB TCP curtain. However, TSPU did add VLESS signatures to its blocklist in December 2025. Recovery required config rotation; providers found the block was signature-specific and responded to parameter changes. REALITY's additional layer of disguise — borrowing a real site's TLS handshake — provides a meaningful margin on the Russia path as well.

VLESS + XTLS-Vision + REALITY addresses the passive and active probing threats:

- **XTLS-Vision** passes the inner TLS record layer through unchanged, making the traffic byte-for-byte indistinguishable from real TLS 1.3 application data. It eliminates the TLS-in-TLS length/timing signature that naive TLS tunnels expose.
- **REALITY** borrows a real third-party site's TLS 1.3 Server Hello and maintains a live connection to that site in reserve. When an active probe arrives, REALITY splices the connection to the real destination and returns the real response — the server is literally indistinguishable from the target site.

For Russia: REALITY is deployed on a random high port (not 443, which triggers instant drops per Feb 2026 analysis) with a clean-IP provider, reducing both the TCP curtain exposure and the VLESS signature detection risk.

## Decision

We hypothesize that deploying VLESS + XTLS-Vision + REALITY with:

- A random high port (47000+) for Russia; port 443 acceptable for China
- A real TLS 1.3 + HTTP/2 serverName in the same ASN/region as the VPS
- `"flow": "xtls-rprx-vision"` enabled
- Client-IP whitelist firewall rules dropping all inbound not from the known client IP

…will complete >1 MB transfers without freeze or reset on both Russia and China paths, and will not be fingerprinted by active probing within 72 h of deployment.

## Experiments

1. **Baseline connectivity (Russia primary):** From a Rostelecom connection, attempt a >1 MB transfer over REALITY at a random high port on a clean-IP provider. Record whether the 16 KB curtain terminates the connection.

2. **72 h GFW durability (China):** From a China-routed vantage, poll the server every 6 h for 72 h with >1 MB transfers. Record any block events.

3. **XTLS-Vision vs. plain VLESS:** Deploy both variants; route traffic through a GFW-emulating entropy classifier (open-source USENIX 2023 implementation). Confirm Vision variant is not flagged.

4. **Client-IP whitelist validation:** Confirm connection attempts from non-whitelisted IPs are silently dropped — no RST, no response — presenting no surface to a probe scanner.

5. **Port 443 vs. high port (Russia):** Deploy on port 443 and a random high port on the same clean-IP provider. Compare 72 h survival on the Russia path.

## Success criteria

- MET-0007: ≥95% of >1 MB transfers complete on Russia path (high port, clean IP) over 72 h; ≥95% on China path over 72 h.
- MET-0008: Probe-replay script receives valid TLS responses on 100% of probes; server IP remains reachable for ≥72 h without manual intervention.
- High port survives ≥2× longer than port 443 on Russia path.

## Consequences

- **If confirmed:** VLESS+VISION+REALITY at a high port on a clean IP becomes the designated primary transport. Port 443 is documented as China-only; high ports are the Russia default.
- **If Russia path fails due to 16 KB curtain:** Expected — the UDP fallback is the designated Russia throughput path. REALITY on TCP remains the stealth primary; throughput falls to the UDP path.
- **If refuted by active probing within 72 h:** serverName selection is the likely weak point — revisit the curation criteria for the Russia and China paths respectively.
- **Ongoing risk:** REALITY serverName domains can be collaterally blocked. The provisioner must maintain a curated, tested list and allow SNI rotation without a full redeploy.
