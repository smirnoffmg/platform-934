# Molecule default scenario — firewall role

## Acceptance criteria exercised

- **AC-3 (idempotency):** `molecule test` runs converge twice; the second
  run reports `changed=0` on both platforms. `flush ruleset` at the top of
  the template plus `ansible.builtin.template`'s content comparison make
  this true regardless of how many times the role is applied.
- **AC-5 (template reflects variables):** `verify.yml` reads
  `/etc/nftables.conf` and asserts the exact port values and
  `client_ip_whitelist` entries from this scenario's `group_vars` appear in
  the rendered file.
- **AC-6 (default-deny with explicit allowances):** `verify.yml` asserts
  `policy drop` on the `input` chain, the Xray/Hysteria2/AmneziaWG port
  accept rules, and that both whitelisted IPs appear in the SSH allowance
  block.

## AC-7 gap (network-level rejection)

AC-7 (a connection from a non-whitelisted IP is refused) requires a real
NIC and network-level enforcement. Docker containers in this scenario share
the host's network stack in ways that make nftables `input`-chain
enforcement unreliable to assert from outside the container, so AC-7 is
excluded here.

### Manual real-VPS test checklist for AC-7

1. Deploy with `client_ip_whitelist: ["<operator-IP>"]`.
2. From the operator IP, confirm SSH succeeds.
3. From a second IP not in the whitelist (e.g., a second cloud instance),
   confirm `ssh -p <ssh_port> <vps-ip>` times out or is refused.
4. Confirm `nft list ruleset` on the VPS shows no `ip saddr <second-IP>`
   rule in the SSH block.
5. Run `make deploy` a second time with no variable changes; confirm
   `changed=0` in the Ansible summary.

## ACs not exercised in Docker

- **`nftables.service` active state:** The Docker images in this scenario
  do not boot with systemd as PID 1 (confirmed empirically: `systemctl
list-units` fails with "System has not been booted with systemd as init
  system. Can't operate."). "Enable and start nftables service" in
  `tasks/install.yml` is guarded with `when: ansible_virtualization_type !=
'docker'` and is skipped here; `verify.yml`'s enabled-state assertion is
  symmetrically guarded. Manual checklist: SSH to a real VPS after `make
deploy`, run `systemctl is-active nftables` — must return exit code 0.

## Lockout-guard edge case

The empty-`client_ip_whitelist` fallback (SSH allowed from any source) is
covered by the separate `empty-whitelist` scenario in this role, not by
this scenario — see `../empty-whitelist/README.md`.

## Images used

| Platform   | Image                                   |
| ---------- | --------------------------------------- |
| ubuntu2204 | `geerlingguy/docker-ubuntu2204-ansible` |
| debian12   | `geerlingguy/docker-debian12-ansible`   |

## How to run

```bash
cd ansible/roles/firewall
molecule test          # full lifecycle: create → prepare → converge → idempotence → verify → destroy
molecule converge      # apply role only (containers remain running)
molecule verify        # run verify.yml against running containers
molecule destroy       # tear down containers
```
