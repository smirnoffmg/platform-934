---
id: SOL-0002
status: proposed
metric_ids:
  - MET-0002
  - MET-0009
---

# UDP Path and Routing Selection for Usable Tunnel Throughput

## Context

Two distinct mechanisms degrade throughput even when the tunnel is technically open and unblocked:

**Russia — TCP throttle (primary concern):** TSPU freezes TLS 1.3/HTTPS-pattern TCP connections to foreign datacenter IPs at ~16 KB, rendering them practically unusable at ~128 kbps. A REALITY tunnel may pass a small connectivity check while sustained throughput is throttled below any usable threshold. MET-0007 passes; MET-0002 fails. This affects Rostelecom, Megafon, Vimpelcom, MTS, and MGTS — the five major Russian ISPs — and has been active since June 2025.

**China — route loss (secondary concern):** China-international transit (especially China Telecom 163 backbone at peak hours) exhibits 5–15% packet loss. TCP head-of-line blocking causes throughput collapse under sustained loss even when the path is not intentionally blocked.

Neither failure mode is a protocol-detection event. Both are infrastructure and routing problems addressed by infrastructure and protocol choices, not stealth improvements.

For Russia, AmneziaWG (UDP) bypasses the TCP throttle entirely because the heuristic targets TCP-pattern connections specifically. On any path with sustained packet loss, Hysteria2's Brutal congestion control maintains throughput by treating loss as bandwidth information rather than a congestion signal. For China, premium routing (CN2 GIA / CTGNet via AS4809, CMIN2 AS58807 for Mobile, AS9929 for Unicom) reduces peak-hour loss to tolerable levels.

## Decision

We hypothesize that:

1. **Russia path:** AmneziaWG (UDP) achieves ≥5 Mbps on Rostelecom and Megafon connections to a foreign datacenter IP by bypassing the TCP throttle heuristic entirely. Where AmneziaWG is blocked, Hysteria2 with Brutal CC provides a throughput fallback.

2. **China path:** Deploying on a CN2 GIA or equivalent low-loss provider achieves ≥5 Mbps by keeping peak-hour packet loss below 1%. On residual high-loss paths, Hysteria2 Brutal maintains ≥5 Mbps where standard TCP stalls.

## Experiments

1. **Russia throughput baseline:** From a Rostelecom connection, measure median 10 MB throughput over REALITY (TCP, expected: throttled ~128 kbps), AmneziaWG (UDP, expected: unthrottled), and Hysteria2. Confirm AmneziaWG achieves ≥5 Mbps where REALITY does not.

2. **Hysteria2 Brutal under loss:** Using `tc netem` to simulate 2%, 5%, and 10% packet loss, measure 10 MB transfer time over Hysteria2 (Brutal CC) vs. REALITY (TCP BBR). Confirm Hysteria2 maintains ≥5 Mbps at 5% loss where TCP falls below threshold.

3. **Route quality comparison (China):** Deploy identical REALITY configs on a CN2 GIA provider and a generic transit provider. Measure median 10 MB throughput from a China-routed vantage at peak and off-peak hours.

4. **Brutal detection tell:** Verify that Hysteria2 Brutal's push-harder-under-throttle behavior does not itself become a detection signal on the Russia path. Compare a throttled Brutal session against a standard QUIC session for additional TSPU responses.

5. **AmneziaWG overhead:** Measure AmneziaWG throughput vs. standard WireGuard on an unthrottled path to quantify junk-packet bandwidth overhead.

## Success criteria

- MET-0002: ≥5 Mbps median on Russia path (AmneziaWG or Hysteria2), ≥5 Mbps on China path (CN2 GIA provider or Hysteria2).
- Hysteria2 Brutal achieves ≥5 Mbps at simulated 5% loss where REALITY TCP falls below 2 Mbps.
- AmneziaWG throughput overhead vs. standard WireGuard: ≤15% reduction in median transfer speed.

## Consequences

- **If Russia UDP throughput confirmed:** AmneziaWG is designated the primary throughput path for Russia; REALITY on TCP is treated as connectivity-only on the Russia path.
- **If Hysteria2 Brutal confirmed:** Designated the throughput-optimized fallback on all high-loss paths. The Brutal detection risk is documented but accepted unless the tell test shows measurable detection acceleration.
- **If CN2 GIA routing confirmed for China:** Provider selection is a documented prerequisite for China usability, not just a performance nicety.
- **Ongoing risk:** Brutal CC's push-harder-under-loss behavior is an identifiable anomaly. If TSPU begins targeting it, Hysteria2 must be reconfigured with standard BBRv2 CC at the cost of throughput on lossy links.
