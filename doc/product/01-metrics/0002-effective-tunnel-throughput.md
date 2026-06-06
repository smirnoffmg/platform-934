---
id: MET-0002
status: proposed
---
# Effective Tunnel Throughput

## What it measures

The sustained transfer speed through a working tunnel on each target path — catching the failure mode where the tunnel is technically connected but throttled to the point of being functionally unusable.

## Definition

**Throughput** = median bytes/second over a 10 MB download through the tunnel, measured from the client vantage point.

A result below threshold is a failure even if the transfer completes — the connection exists but is not usably fast.

## Collection method

Timed 10 MB download through the active tunnel protocol (REALITY primary; fallback protocols tested independently) run from:

- A Rostelecom or Megafon connection (TSPU path, primary)
- A China-routed vantage point (GFW path, secondary)

Tests run at deployment time and every 24 h. Median of 3 consecutive runs reported per path.

## Threshold

- Russia path: ≥ 5 Mbps median (via AmneziaWG UDP path, which bypasses the TCP throttle; REALITY TCP path not expected to meet this threshold on affected ISPs)
- China path: ≥ 5 Mbps median (via CN2 GIA or equivalent low-loss routing)

## Rationale

MET-0001 through MET-0007 measure connectivity — whether transfers complete. None of them catch Russia's primary suppression tactic against self-hosters as of June 2025: throttling TLS 1.3 connections to foreign datacenter IPs to ~128 kbps while leaving the connection technically open. A user whose tunnel is throttled to 128 kbps has effectively no internet access, but every other metric would show green.
