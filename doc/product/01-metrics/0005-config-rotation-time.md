---
id: MET-0005
status: proposed
problem_hypothesis_id: PROB-0001
---

# Configuration Rotation Time

## What it measures

How long `make rotate` takes to change port, SNI, and/or IP and restore verified end-to-end connectivity, without any manual intervention after the command is issued.

## Definition

**Rotation time** = wall-clock seconds from `make rotate` invocation to the moment the post-rotate connectivity check (>1 MB transfer through the rotated REALITY tunnel) passes.

Rotation must cover at minimum: new listening port, new REALITY `serverName` (SNI), regenerated key pair. IP rotation (new VPS) is measured separately as a superset case.

## Collection method

Timed locally against a live VPS for port+SNI rotation, and in CI for full IP rotation (teardown + re-provision). Median of 5 runs reported.

## Threshold

- Port + SNI rotation: ≤ 5 minutes (300 seconds) median.
- Full IP rotation (new VPS): ≤ 20 minutes (1200 seconds) median (deploy time + DNS TTL).

## Rationale

Rotation is the escape valve when a config is burned. The shorter the rotation cycle, the lower the cost of detection, and the more aggressive the user can be about discarding suspected configs without worrying about extended downtime. Rotation time and burn detection latency (MET-0004) are additive — total recovery time = detection latency + rotation time. Keeping both under their respective thresholds bounds total recovery under 7 minutes in the worst case.
