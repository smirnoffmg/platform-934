---
id: MET-0006
status: proposed
---
# Deployment Convergence Time

## What it measures

How long it takes `make deploy` to bring a fresh, unconfigured VPS to a fully operational state — all protocols running, firewall rules applied, secrets in place — without any manual intervention.

## Definition

**Convergence time** = wall-clock seconds from `make deploy` invocation to the moment the automated post-deploy connectivity check (>1 MB transfer through REALITY tunnel) passes.

## Collection method

Timed in CI/CD on a freshly provisioned VPS (cloud-init complete, no prior Ansible state) across three target providers: one clean-IP provider recommended for Russia, one Asia-Pacific provider for China, one generic European provider as baseline. Median of 3 runs per provider reported.

## Threshold

Median convergence time ≤ 15 minutes (900 seconds) across all tested providers.

## Rationale

Fast deployment is the operational foundation of the rotation strategy. If a configuration is detected and blocked, the user must be able to stand up a replacement cheaply. A 15-minute ceiling makes rotation a low-friction response rather than a multi-hour recovery operation.
