# Molecule empty-whitelist scenario — firewall role

## Purpose

Covers the lockout-guard edge case called out in TASK-0006: when
`client_ip_whitelist` is `[]`, the rendered ruleset must allow SSH from any
source rather than blocking it entirely. An operator who deploys with no
whitelist configured must not be locked out of their own VPS.

This is a separate scenario (rather than a second play inside the
`default` scenario's `verify.yml`) because the assertion depends on a
different `client_ip_whitelist` value at converge time, not just at verify
time — `verify.yml` only inspects files already rendered by `converge.yml`,
it cannot change the variables a prior converge used.

## What it checks

`verify.yml` asserts the rendered `/etc/nftables.conf` contains the SSH
fallback rule (`tcp dport 22 accept`) and contains no `ip saddr` rule at
all (proving no whitelist-specific rule was emitted).

## Scope

Single platform (`ubuntu2204`) — OS compatibility is already covered by the
`default` scenario's two platforms; this scenario's only job is to exercise
the template's empty-list branch.

## How to run

```bash
cd ansible/roles/firewall
molecule test -s empty-whitelist
```
