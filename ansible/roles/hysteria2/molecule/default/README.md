# Molecule default scenario — hysteria2 role

## Acceptance criteria exercised

- **AC-3 (idempotency):** `molecule test` runs converge twice; the second run reports `changed=0` on both platforms. `get_url` (checksum-guarded) makes binary installation idempotent; `ansible.builtin.template`/`copy` only report `changed` when rendered output differs from disk.
- **AC-4 (variable-rotation):** Changing `hysteria2_port` on a subsequent converge produces `changed=1` for the "Template config.yaml" task only and notifies the `Restart hysteria2` handler exactly once. No Xray or AmneziaWG tasks or handlers are present in this scenario.
- **AC-5 (config contents):** `verify.yml` reads `/etc/hysteria2/config.yaml` and asserts the port and obfs password from the scenario's group_vars appear verbatim in the rendered file.
- **AC-11 (Molecule scenario passes in CI):** `.github/workflows/molecule.yml` runs this scenario on push/PR.

## ACs not exercised in Docker

- **AC-1 (`systemctl is-active hysteria2`):** The Docker images in this scenario do not boot with systemd as PID 1 (confirmed empirically: `daemon-reload` fails with "System has not been booted with systemd as init system"). The "Enable and start hysteria2.service" task, the `Reload systemd daemon` handler, and the `Restart hysteria2` handler are all guarded with `when: ansible_virtualization_type != 'docker'` and are skipped here. `verify.yml`'s service-enabled assertion is symmetrically guarded and skipped. Manual checklist: SSH to a real VPS after `make deploy`, run `systemctl is-active hysteria2` — must return exit code 0.
- **AC-2 (deploy time ≤ 15 min):** Binary download speed depends on real network conditions; Docker I/O does not reflect a real VPS. No timing assertion is included.

## Variable-rotation test procedure

```bash
molecule converge                                        # hysteria2_port: 10443 (default in molecule.yml)
sed -i '' 's/hysteria2_port: 10443/hysteria2_port: 10444/' molecule/default/molecule.yml
molecule converge                                        # must report changed=1 (config template task only)
sed -i '' 's/hysteria2_port: 10444/hysteria2_port: 10443/' molecule/default/molecule.yml  # restore before molecule verify/destroy
```

The second run must report `changed=1` only for "Template config.yaml" and show the `Restart hysteria2` handler notified (its body is skipped in Docker per the guard above). No Xray or AmneziaWG tasks appear because this scenario applies only the `hysteria2` role.

## Known gaps

- `hysteria2_tls_cert` / `hysteria2_tls_key` in `molecule.yml` are throwaway base64 placeholders, not a real certificate/key pair — this role writes whatever they decode to without parsing or validating it. Real certificate provisioning happens via FEAT-0002 (SOPS); this scenario only exercises file placement and permissions.
- The firewall role (TASK-0006) must open `hysteria2_port` as **UDP**, not TCP — Hysteria2 is QUIC-based. This scenario does not touch the firewall and cannot catch a TCP/UDP mismatch there.
- The `Enable and start hysteria2.service`, `Reload systemd daemon`, and `Restart hysteria2` handler bodies are all no-ops in this scenario (Docker guard). Real systemd lifecycle behavior is only verified on a real VPS.

## Images used

| Platform   | Image                                   |
| ---------- | --------------------------------------- |
| ubuntu2204 | `geerlingguy/docker-ubuntu2204-ansible` |
| debian12   | `geerlingguy/docker-debian12-ansible`   |

## Maintenance note

`hysteria2_version` and `hysteria2_binary_sha256` in `roles/hysteria2/vars/main.yml` must be updated for every upstream Hysteria2 release. This scenario pins concrete values and will fail `molecule converge` on a checksum mismatch. Unlike the Xray role, there is no `creates:`-guarded `unarchive` step — the changed checksum alone causes `get_url` to re-download and overwrite `/usr/local/bin/hysteria2` automatically; no manual file removal is needed for version upgrades.

## How to run

```bash
cd ansible/roles/hysteria2
molecule test          # full lifecycle: create → prepare → converge → idempotence → verify → destroy
molecule converge      # apply role only (containers remain running)
molecule verify         # run verify.yml against running containers
molecule destroy       # tear down containers
```
