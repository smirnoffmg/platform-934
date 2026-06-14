---
id: SOL-0010
status: proposed
metric_ids:
  - MET-0010
  - MET-0001
---

# Multi-Protocol Fallback Stack

## Context

No single protocol survives indefinitely in an adaptive censorship environment. Protocol "death dates" demonstrate this concretely: Trojan ~90% detected by Aug 2025, VMess ~80% by Sept 2025, TSPU added VLESS signatures in Dec 2025, and AmneziaWG signatures have been added and updated in TSPU's database periodically. Each detection event is survivable if a working fallback is immediately available — it becomes a service failure only if all protocols are simultaneously blocked.

The detection-to-rotation interval (MET-0004 + MET-0005) is the window during which the user has no working primary protocol and needs a fallback to maintain connectivity. If the fallback requires manual reconfiguration during this window, the user is effectively offline until they intervene.

For Russia, the fallback stack is ordered by threat model:

1. **REALITY (TCP):** primary; stealth-focused, may be throttled by 16 KB curtain on some ISPs/IPs
2. **AmneziaWG (UDP):** primary Russia fallback; bypasses TCP curtain, obfuscates WireGuard signature
3. **Hysteria2 (QUIC/UDP):** tertiary; HTTP/3 masquerade, robust on lossy paths, but QUIC is more visible than AmneziaWG's UDP and China's GFW has inspected QUIC SNI since April 2024

For China, the fallback stack is simpler:

1. **REALITY (TCP):** primary
2. **Hysteria2 (QUIC):** fallback for lossy paths; AmneziaWG's UDP obfuscation is not targeted at GFW entropy classification

Client-side failover should be automatic: the client's routing rules try the primary protocol first, fall through to AmneziaWG, then Hysteria2, without manual reconfiguration.

## Decision

We hypothesize that deploying all three protocols on separate ports — REALITY on a random high TCP port, AmneziaWG on a random high UDP port, Hysteria2 on a separate random high UDP port — with automatic client failover will achieve ≥90% fallback success rate when the primary protocol is blocked, across 5 test runs each for AmneziaWG and Hysteria2 as fallbacks.

## Experiments

1. **AmneziaWG fallback (Russia primary):** Block the REALITY TCP port at the server firewall. From a Rostelecom connection, verify the client routes >1 MB through AmneziaWG without manual reconfiguration. Repeat 5 times.

2. **Hysteria2 fallback (AmneziaWG blocked):** Block both REALITY and AmneziaWG ports. Verify the client routes >1 MB through Hysteria2 without manual reconfiguration. Repeat 5 times.

3. **Hysteria2 fallback (China):** Block the REALITY port. From a China-routed vantage, verify the client routes >1 MB through Hysteria2. Repeat 5 times.

4. **Failover latency:** Measure time from primary protocol failure to first successful byte through the fallback protocol. Confirm failover completes within 30 seconds.

5. **All-blocked scenario:** Block all three protocol ports simultaneously. Confirm the client fails gracefully (clear error, no silent hang) and the polling daemon (MET-0004) registers the failure correctly.

## Success criteria

- MET-0010: AmneziaWG achieves ≥90% success rate across 5 runs with REALITY blocked on Russia path; Hysteria2 achieves ≥90% across 5 runs with AmneziaWG also blocked.
- Failover latency: ≤30 seconds from primary failure to first fallback byte.
- All-blocked scenario: client fails with a clear error within 2 minutes, polling daemon registers failure within MET-0004 threshold.

## Consequences

- **If confirmed:** All three protocols are provisioned by default as a unit. Removing any protocol from the stack requires explicit justification.
- **If AmneziaWG fallback fails:** Russia has no working fallback when REALITY is blocked. This is escalated: either AmneziaWG's junk parameters need tuning or a different UDP-based protocol must be evaluated.
- **If Hysteria2 fallback fails on China path:** QUIC is being blocked or degraded on the test path. Hysteria2's masquerade settings (ALPN, SNI) need adjustment, or a TCP-based secondary must be added for China.
- **Ongoing risk:** Automatic client failover depends on the client implementation correctly ordering protocols and timing out cleanly. Misconfigured failover order (e.g., always trying Hysteria2 first on Russia) will degrade performance even when REALITY is working.
