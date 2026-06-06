---
id: MET-0004
status: proposed
---
# Burn Detection Latency

## What it measures

The time between a config being blocked by censors and the client detecting the failure — the silent downtime window during which the user has no connectivity but doesn't yet know to rotate.

## Definition

**Burn detection latency** = time from actual block event to the moment the polling daemon (MET-0001) registers a failure.

Measured in a controlled test environment by firewalling the REALITY port on the server side and timing how long until the daemon logs a failure.

## Collection method

1. Deploy a live server with the polling daemon running.
2. Block the REALITY port at the server firewall (simulating a censor block event).
3. Record the timestamp of the firewall rule and the timestamp of the first daemon failure log entry.
4. Latency = daemon failure timestamp − firewall timestamp.

Repeated 5 times per protocol (REALITY, AmneziaWG, Hysteria2). Median reported.

## Threshold

≤ 2 minutes median burn detection latency across all tested protocols.

## Rationale

Burn detection latency is dead downtime: the user is disconnected but the system hasn't triggered recovery yet. With a 60-second polling interval, the theoretical minimum is 60 seconds; the threshold of 2 minutes allows for one missed poll or a slow TCP timeout before the daemon registers failure. Detection latency and rotation time (MET-0005) are additive — total recovery time = detection latency + rotation time. Keeping detection latency under 2 minutes means total recovery stays within the 5-minute bound that makes rotation operationally tolerable.
