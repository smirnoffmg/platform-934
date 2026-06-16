# Molecule default scenario — xray role

## Acceptance criteria exercised

- **AC-3 (idempotency):** `molecule test` runs converge twice; the second run reports `changed=0` on both platforms. `get_url` (checksum-guarded) and `unarchive` (`creates:`-guarded) make binary installation idempotent; `ansible.builtin.template` only reports `changed` when rendered output differs from disk.
- **AC-4 (variable-rotation):** Changing `xray_port` on a subsequent converge produces `changed=1` for the "Template config.json" task only and notifies the `Restart xray` handler exactly once. No AmneziaWG or Hysteria2 tasks or handlers are present in this scenario.
- **AC-5 (config contents):** `verify.yml` reads `/etc/xray/config.json` and asserts the port, UUID, and serverName from the scenario's group_vars appear verbatim in the rendered file.
- **AC-11 (Molecule scenario passes in CI):** `.github/workflows/molecule.yml` runs this scenario on push/PR.

## ACs not exercised in Docker

- **AC-1 (`systemctl is-active xray`):** The Docker images in this scenario do not boot with systemd as PID 1 (confirmed empirically: `daemon-reload` fails with "System has not been booted with systemd as init system"). The "Enable and start xray.service" task, the `Reload systemd` handler, and the `Restart xray` handler are all guarded with `when: ansible_virtualization_type != 'docker'` and are skipped here. `verify.yml`'s service-enabled assertion is symmetrically guarded and skipped. Manual checklist: SSH to a real VPS after `make deploy`, run `systemctl is-active xray` — must return exit code 0.
- **AC-2 (deploy time ≤ 15 min):** Binary download speed depends on real network conditions; Docker I/O does not reflect a real VPS. No timing assertion is included.

## Variable-rotation test procedure

```bash
molecule converge                                  # xray_port: 10443 (default in molecule.yml)
sed -i '' 's/xray_port: 10443/xray_port: 10444/' molecule/default/molecule.yml
molecule converge                                  # must report changed=1 (config template task only)
sed -i '' 's/xray_port: 10444/xray_port: 10443/' molecule/default/molecule.yml  # restore before molecule verify/destroy
```

The second run must report `changed=1` only for "Template config.json" and show the `Restart xray` handler notified (its body is skipped in Docker per the guard above). No AmneziaWG or Hysteria2 tasks appear because this scenario applies only the `xray` role.

## Known gaps

- `xray_private_key` / `xray_public_key` in `molecule.yml` are a throwaway X25519 test keypair generated solely for this scenario — they are not used anywhere real. Xray's `validate:` step (`xray run -test -config %s`) parses `privateKey` as a well-formed X25519 scalar, so an arbitrary placeholder string fails config validation; this is the same strictness production deploys rely on, so the scenario exercises it directly.
- The `creates: /usr/local/bin/xray` guard on the `unarchive` task means a `xray_version` bump alone does not replace an already-installed binary. See the role's maintenance note below.
- The `Enable and start xray.service`, `Reload systemd`, and `Restart xray` handler bodies are all no-ops in this scenario (Docker guard). Real systemd lifecycle behavior is only verified on a real VPS.

## Images used

| Platform   | Image                                   |
| ---------- | --------------------------------------- |
| ubuntu2204 | `geerlingguy/docker-ubuntu2204-ansible` |
| debian12   | `geerlingguy/docker-debian12-ansible`   |

## Maintenance note

`xray_version` and `xray_archive_sha256` in `roles/xray/vars/main.yml` must be updated for every upstream Xray-core release. This scenario pins concrete values and will fail `molecule converge` on a checksum mismatch. Upgrading the binary on an already-provisioned host additionally requires removing `/usr/local/bin/xray` first (or changing the `creates:` guard in `tasks/install.yml`) — bumping the version alone does not trigger re-extraction.

## How to run

```bash
cd ansible/roles/xray
molecule test          # full lifecycle: create → prepare → converge → idempotence → verify → destroy
molecule converge      # apply role only (containers remain running)
molecule verify         # run verify.yml against running containers
molecule destroy       # tear down containers
```
