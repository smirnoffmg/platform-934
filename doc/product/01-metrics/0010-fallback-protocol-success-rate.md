---
id: MET-0010
status: proposed
problem_hypothesis_id: PROB-0001
---

# Fallback Protocol Success Rate

## What it measures

Whether at least one fallback protocol (AmneziaWG for Russia; Hysteria2 for high-loss links) successfully completes a transfer when the REALITY primary is simulated as blocked, confirming the fallback stack provides real redundancy.

## Definition

**Success** = with the REALITY port firewalled on the server side (simulating a burn event), a >1 MB transfer completes through the designated fallback protocol (AmneziaWG or Hysteria2, tested independently) without manual reconfiguration on the client.

## Collection method

1. Deploy full stack (REALITY + AmneziaWG + Hysteria2).
2. Block the REALITY port at the server firewall.
3. Verify client failover to AmneziaWG completes a >1 MB transfer (Russia path).
4. Repeat blocking AmneziaWG port; verify Hysteria2 fallback (high-loss path simulated with `tc netem`).

Tests run from both a Russia-routed vantage point (AmneziaWG primary fallback) and a generic high-loss path (Hysteria2).

## Threshold

Both AmneziaWG and Hysteria2 independently achieve ≥ 90 % success rate across 5 test runs each on their respective target paths.

## Rationale

No single protocol survives indefinitely in an adaptive censorship environment. Fallback coverage is the safety net that keeps the user connected through the interval between detection and full rotation. This metric validates that the safety net is functional, not theoretical.
