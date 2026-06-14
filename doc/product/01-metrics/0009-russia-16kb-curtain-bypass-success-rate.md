---
id: MET-0009
status: proposed
problem_hypothesis_id: PROB-0001
---

# Russia 16 KB Curtain Bypass Success Rate

## What it measures

Whether the AmneziaWG (obfuscated WireGuard) tunnel can sustain transfers well beyond the ~16 KB TSPU freeze threshold on affected Russian ISPs, confirming the curtain heuristic is defeated.

## Definition

**Success** = a >100 KB transfer completes through the AmneziaWG tunnel without freeze or timeout on a Rostelecom or Megafon connection to a foreign datacenter IP.

## Collection method

Automated transfer test run from:

- A Rostelecom residential connection (primary)
- A Megafon connection (secondary, if available)

Transfer sizes tested: 100 KB, 1 MB, 10 MB. Each size attempted 5 times. Tests run at deployment time and every 12 h for 72 h.

## Threshold

≥ 90 % of 100 KB transfers complete successfully on at least one TSPU-affected ISP path.

## Rationale

The TSPU 16 KB curtain specifically targets TLS 1.3 / HTTPS-pattern connections to foreign datacenter IP ranges. AmneziaWG uses UDP with a different packet structure and junk-packet obfuscation; this metric directly validates whether that difference is sufficient to avoid the freeze heuristic. The 100 KB threshold is ~6× the curtain boundary, providing meaningful margin.
