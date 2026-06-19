# Real-VPS testing checklist

Molecule (Docker driver) covers most of FEAT-0001's acceptance criteria in CI.
Four ACs are explicitly out of Docker's reach — see
`doc/product/03-features/0001-idempotent-ansible-playbook-core.md` for why —
and must be checked manually on a real VPS before merging any change to the
`amneziawg` or `firewall` roles. This doc is that manual run, step by step.

## Setup

```bash
doctl auth init                          # once, if not already authenticated
scripts/test-vps-up.sh ubuntu            # or: debian
```

Fill in real values in `ansible/vars/real.secret.yml` (gitignored — see that
file's header for what generates each value), then converge:

```bash
ansible-playbook -i ansible/inventory/hosts.test.ini ansible/playbook.yml \
  -e @ansible/vars/real.secret.yml
```

## AC-1 (partial) — AmneziaWG module loaded

```bash
ssh root@<droplet-ip> 'lsmod | grep amneziawg'
```

Expect: exit code 0, module listed. (The rest of AC-1 — `systemctl is-active
xray`/`hysteria2` — is already covered by Molecule.)

## AC-2 — cold deploy time ≤ 15 minutes

Time the playbook run above, wall clock, from invocation to completion:

```bash
time ansible-playbook -i ansible/inventory/hosts.test.ini ansible/playbook.yml \
  -e @ansible/vars/real.secret.yml
```

Expect: `real` ≤ 15m. (FEAT-0001's AC-2 asks for a median across 3 runs on
each of three provider tiers — this single-run check is a fast sanity check,
not the full AC-2 measurement campaign.)

## AC-3/AC-4 sanity re-check — idempotency on real hardware

Molecule already asserts this in Docker; re-running on the real box is cheap
extra confidence:

```bash
ansible-playbook -i ansible/inventory/hosts.test.ini ansible/playbook.yml \
  -e @ansible/vars/real.secret.yml
```

Expect: `changed=0 failed=0` in the play recap.

## AC-7 — client-IP whitelist enforced at the network level

Requires `client_ip_whitelist` in `real.secret.yml` set to your real test
IP, not `[]`.

```bash
# From a whitelisted IP — should succeed:
ssh -o ConnectTimeout=5 root@<droplet-ip> true && echo "OK: whitelisted IP allowed"

# From a non-whitelisted IP (e.g. a phone hotspot, or curl a "what's my IP"
# service first to confirm which IP you're testing from) — should fail:
ssh -o ConnectTimeout=5 root@<droplet-ip> true && echo "FAIL: should have been rejected"
```

## AC-8 — AmneziaWG survives reboot

```bash
ssh root@<droplet-ip> 'shutdown -r now'
# wait for SSH to come back, then:
ssh root@<droplet-ip> 'lsmod | grep amneziawg'
```

Expect: module present within 60 seconds of SSH becoming reachable again,
with no manual intervention and no re-running the playbook.

## Teardown

```bash
scripts/test-vps-down.sh
```

Don't skip this — the droplet bills hourly until destroyed.
