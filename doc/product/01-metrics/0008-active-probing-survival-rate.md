---
id: MET-0008
status: proposed
problem_hypothesis_id: PROB-0001
---

# Active-Probing Survival Rate

## What it measures

Whether the server correctly handles replayed GFW-style active probes — forwarding them transparently to the REALITY fallback destination — so that the server is not flagged and blocked within 72 h of first use.

## Definition

**Survival** = the server IP remains unblocked (reachable on its configured port) 72 h after deployment, AND a probe-replay script (sending GFW-style replayed TLS ClientHellos and raw TCP payloads) receives a valid response indistinguishable from the legitimate fallback site.

## Collection method

1. A probe-replay script (mimicking documented GFW replay probe patterns from USENIX Security 2023) is run against the deployed server from a neutral vantage point immediately after deployment.
2. Server reachability is polled every 6 h for 72 h from a China-routed vantage point.

## Threshold

- Probe-replay script receives a valid TLS response (not a connection reset) on 100 % of probe attempts.
- Server IP remains reachable for ≥ 72 h post-deployment without manual intervention.

## Rationale

GFW active probing is the primary mechanism that kills "looks-like-TLS" servers quickly. REALITY's distinguishing feature is transparently forwarding probes to a real site; this metric directly validates that property.
