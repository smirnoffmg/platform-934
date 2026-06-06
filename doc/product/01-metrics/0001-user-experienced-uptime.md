---
id: MET-0001
status: proposed
---
# User-Experienced Uptime

## What it measures

The percentage of time the user has working internet access through the tunnel, measured continuously from their actual client machine in Russia (primary) or China (secondary), including all downtime from detection events, rotation operations, protocol failures, and provider outages.

## Definition

**Uptime** = (total measurement window − total downtime) / total measurement window × 100%

**Downtime** begins when a connectivity poll fails and ends when it succeeds again. A poll fails if a fetch of a known external URL through the tunnel does not complete within 10 seconds.

Measured over a rolling 30-day window.

## Collection method

A polling daemon runs on the client machine and attempts a fetch of a stable external URL (e.g., `https://www.google.com`) through the tunnel every 60 seconds. Results are logged locally with timestamps. Downtime intervals are summed at the end of each 30-day window.

Rotation operations contribute to downtime naturally — the clock keeps running during `make rotate`.

## Threshold

≥ 95% uptime over any 30-day measurement window (≤ 36 hours total downtime per month).

## Rationale

This is the only metric that directly answers whether the problem hypothesis is solved. All other metrics are technical properties of the solution — they can all be green while the user is still experiencing unacceptable outages due to frequent detection cycles, slow rotation, or provider issues. A 95% threshold over 30 days represents a practical definition of "reliable": it tolerates several burn-and-rotate events per month while failing if detection frequency or rotation latency makes the connection structurally unusable.
