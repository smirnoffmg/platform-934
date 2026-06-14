---
id: SOL-0009
status: proposed
metric_ids:
  - MET-0009
  - MET-0010
  - MET-0002
---

# AmneziaWG UDP Tunnel for Russia 16 KB Curtain Bypass

## Context

TSPU's 16 KB curtain freezes TLS 1.3/HTTPS-pattern TCP connections to foreign datacenter IPs after ~25 packets (~16 KB), regardless of the proxy protocol running inside the tunnel. This mechanism has been active on Rostelecom, Megafon, Vimpelcom, MTS, and MGTS since June 2025. It targets the outer TCP connection pattern — not the inner protocol — so any TCP-based tunnel (REALITY, naiveproxy, Trojan, plain WireGuard over TCP) is affected when connecting to a flagged IP range.

Standard WireGuard is a non-starter: TSPU has its handshake signature in the blocklist. OpenVPN, IKEv2, L2TP, and PPTP are similarly blocked by DPI signature.

AmneziaWG addresses both problems simultaneously:

1. **UDP bypasses the TCP curtain:** The 16 KB heuristic targets TCP-pattern connections. AmneziaWG is UDP-based and is entirely unaffected by the curtain mechanism.

2. **Junk-packet obfuscation destroys the WireGuard DPI signature:** AmneziaWG prepends configurable amounts of random junk data (`Jc`, `Jmin`, `Jmax` parameters) to each WireGuard handshake and data packet. This eliminates the fixed-format WireGuard handshake that TSPU's DPI matches against. The `H1`–`H4` and `S1`/`S2` parameters further randomize initiator and responder headers.

AmneziaWG is therefore the designated primary fallback for the Russia path — not a secondary option behind REALITY, but the first protocol to try when the TCP path is frozen.

## Decision

We hypothesize that deploying AmneziaWG with junk parameters (`Jc=4, Jmin=40, Jmax=70` as the baseline; large-junk variant `Jc=1, Jmin=1200, Jmax=1300` as an alternative) on a random high UDP port will:

1. Complete >100 KB transfers without freeze on Rostelecom and Megafon connections to a foreign datacenter IP.
2. Evade WireGuard DPI signature detection for ≥72 h post-deployment.
3. Maintain throughput within 15% of standard WireGuard on an unthrottled path (junk packets add overhead; this bounds acceptable waste).

The `Jc`/`Jmin`/`Jmax` parameters are Ansible template variables, re-tunable without full redeployment.

## Experiments

1. **16 KB curtain bypass:** From a Rostelecom connection, transfer 100 KB, 1 MB, and 10 MB through AmneziaWG to a foreign datacenter IP. Record completion rate and whether any freeze occurs. Run a standard WireGuard tunnel on the same path as a negative control (expected: blocked by DPI signature or frozen by curtain).

2. **Junk parameter tuning:** Test baseline (`Jc=4, Jmin=40, Jmax=70`) and large-junk (`Jc=1, Jmin=1200, Jmax=1300`) variants. Measure which avoids DPI detection while maintaining acceptable throughput overhead.

3. **72 h survival:** From a Rostelecom or Megafon connection, poll the AmneziaWG port every 6 h for 72 h with >1 MB transfers. Record any block events.

4. **Throughput overhead:** On an unthrottled reference path, measure AmneziaWG throughput vs. standard WireGuard with identical server hardware and network conditions. Confirm overhead ≤15%.

5. **DKMS reboot survival:** After a VPS kernel update and reboot, confirm the AmneziaWG kernel module is rebuilt by DKMS and the service restores without manual intervention.

## Success criteria

- MET-0009: ≥90% of >100 KB transfers complete on at least one TSPU-affected ISP (Rostelecom or Megafon) within 72 h of deployment.
- Standard WireGuard negative control: blocked or frozen on same path (validates that the bypass is specific to AmneziaWG's obfuscation, not a general UDP allowance).
- AmneziaWG throughput overhead vs. standard WireGuard: ≤15% on unthrottled path.

## Consequences

- **If confirmed:** AmneziaWG becomes the designated Russia primary fallback in the provisioner. Standard WireGuard is explicitly excluded. Junk parameters are documented defaults with re-tuning instructions.
- **If TSPU adds AmneziaWG UDP signature:** TSPU has periodically updated its signature database. Re-tuning `Jc`/`Jmin`/`Jmax` has historically restored function. If re-tuning fails, this becomes PROB-0002: no TCP-or-UDP path exists to the Russia target without a domestic relay hop.
- **If UDP is rate-limited rather than blocked:** AmneziaWG connections persist but at reduced throughput — falls to MET-0002 evaluation. Hysteria2 on a different UDP port may be less targeted.
- **Ongoing risk:** AmneziaWG requires a kernel module (DKMS). Kernel updates that break the module before DKMS rebuilds it cause an outage. The post-deploy and periodic healthchecks must verify the module is loaded.
