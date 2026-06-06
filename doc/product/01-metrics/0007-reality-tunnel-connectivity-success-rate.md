---
id: MET-0007
status: proposed
---
# REALITY Tunnel Connectivity Success Rate

## What it measures

Whether a VLESS + XTLS-Vision + REALITY tunnel can complete a non-trivial transfer on both a GFW-routed (China) and a TSPU-routed (Russia) test path without being frozen, reset, or blocked.

## Definition

**Success** = a >1 MB HTTP(S) transfer through the tunnel completes end-to-end without a TCP RST, freeze, or timeout, measured from a client on each target ISP path.

## Collection method

Automated test script run from:

- A Rostelecom or Megafon connection (TSPU path, primary)
- A China-exiting VPS or residential proxy (GFW path, secondary)

Tests run immediately after deployment and at 24 h intervals for 72 h.

## Threshold

≥ 95 % success rate across 10 consecutive transfer attempts per path, sustained over 72 h post-deployment.

## Rationale

A single large transfer exercises both the handshake (active-probing surface) and sustained data flow (volume/entropy classifiers). 72 h captures delayed active-probe reactions common in GFW operation.
