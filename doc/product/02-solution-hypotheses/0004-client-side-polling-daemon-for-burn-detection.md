---
id: SOL-0004
status: proposed
problem_hypothesis_id: PROB-0001
target_metric_id: MET-0004
secondary_metric_ids:
  - MET-0001
---
# Client-Side Polling Daemon for Burn Detection

## Context

After a config is burned, the user experiences silent downtime until the monitoring system detects the failure and triggers recovery. This silent gap — burn detection latency — is dead downtime that adds directly to MET-0001.

Two different failure signatures must be detected:

**Russia — freeze signature:** The TSPU 16 KB curtain does not send a TCP RST. It freezes the connection: packets stop flowing, but the TCP socket remains open. A naive connectivity check that relies on a TCP RST to detect failure will wait for the kernel's full TCP timeout (which defaults to minutes) before registering a problem. The daemon must use an explicit application-level timeout, not a TCP-level one, to catch freezes quickly.

**China — RST injection:** The GFW injects TCP RSTs. These arrive quickly and would be caught by any TCP-level check. The risk here is false positives from transient RSTs on a busy path.

A further complication is false positives: a single failed poll on a lossy path does not mean the config is burned. Requiring two consecutive failures before raising a burn event bounds the false-positive rate, at the cost of one additional polling interval of latency in the worst case.

## Decision

We hypothesize that a polling daemon with the following design will detect burn events within ≤2 minutes on both Russia and China paths:

- Polls every 60 seconds by attempting a fetch of a stable external URL through the tunnel.
- Uses an explicit 10-second application-level timeout (not relying on TCP timeout) to catch both RSTs and freezes.
- Requires 2 consecutive failures before raising a burn alert, to suppress transient false positives.
- On burn alert, logs the event with timestamp and triggers `make rotate` automatically (or alerts the user, depending on configured mode).

Worst-case detection latency under this design: burn occurs just after a passing poll → 60 s to first failing poll → 60 s to confirming poll → alert at 120 s. This is within the 2-minute threshold.

## Experiments

1. **Freeze detection (Russia):** On a live server, firewall the REALITY port. Measure time from firewall rule application to daemon failure log entry, with default TCP timeout vs. 10-second explicit timeout. Confirm explicit timeout detects the freeze within 2 minutes.

2. **RST detection (China):** On a live server, inject a TCP RST (via iptables `-j REJECT --reject-with tcp-reset`) and measure detection latency. Confirm it does not exceed 2 minutes.

3. **False positive rate:** Introduce 1% and 5% random packet loss via `tc netem` without blocking the port. Run for 24 h. Confirm the daemon does not raise spurious burn alerts under either loss rate.

4. **Consecutive-failure threshold:** Test daemon behavior with 1-failure and 3-failure thresholds in addition to 2-failure. Report false-positive rate and additional latency introduced by each threshold.

5. **Auto-rotate integration:** Confirm that when the daemon raises a burn alert in auto-rotate mode, `make rotate` is triggered and completes within MET-0005 threshold without additional manual intervention.

## Success criteria

- MET-0004: ≤2 minutes median burn detection latency under both freeze and RST failure modes.
- Zero false-positive burn alerts over 24 h of 5% packet loss simulation.
- Auto-rotate trigger confirmed functional end-to-end in 5 out of 5 test burn events.

## Consequences

- **If confirmed:** The polling daemon (and its 60s/10s-timeout/2-consecutive-failure configuration) becomes the standard monitoring component shipped with the provisioner.
- **If freeze detection misses the 2-minute threshold:** The polling interval must be reduced (e.g., 30 s), or the TCP timeout detection replaced with an active keepalive that forces traffic through the tunnel, making freezes detectable faster.
- **If false-positive rate is unacceptable:** Raise the consecutive-failure threshold to 3, accepting up to 3 minutes worst-case detection latency in exchange for zero false positives.
- **Ongoing risk:** The daemon runs on the client machine and depends on client uptime. If the client is offline or the daemon crashes, burns go undetected. The daemon should be a systemd service (or launchd on macOS) with restart-on-failure.
