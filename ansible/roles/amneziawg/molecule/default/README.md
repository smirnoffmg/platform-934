# Molecule default scenario — amneziawg role

## Acceptance criteria exercised

- **AC-3 (idempotency):** `molecule test` runs converge twice; the second run must report `changed=0`. All tasks use `creates:` guards, `stat`-conditional skips, or module-level idempotency (e.g. `ansible.builtin.copy` by checksum).
- **AC-4 (variable-rotation idempotency):** Changing `awg_jc` on a subsequent converge produces `changed=1` (template task only) and fires the restart handler exactly once. Xray and Hysteria2 are not present in this scenario.
- **AC-5 (config contents):** `verify.yml` reads `/etc/amnezia/amneziawg/awg0.conf` and asserts `ListenPort`, `Jc`, `Jmin`, and `Jmax` match the scenario variables.
- **AC-11 (Molecule scenario passes):** `molecule test` runs end-to-end without manual steps.

## ACs not exercised in Docker

- **AC-1 (`lsmod | grep amneziawg`):** Docker containers share the host kernel. DKMS cannot build or install a module inside the container. Manual checklist: SSH to real VPS after first deploy, run `lsmod | grep amneziawg` — must return exit code 0.
- **AC-8 (kernel module persistence after reboot):** Cannot simulate a reboot in Docker. Manual checklist: reboot the VPS, wait ≤60 s for SSH, run `lsmod | grep amneziawg` without re-running `make deploy`.
- **AC-2 (DKMS build time ≤15 min):** DKMS build is skipped in Docker. Manual checklist: time the `dkms build` step on a clean VPS; if it consistently exceeds 5 min, open a follow-up task to evaluate pre-built DKMS packages.

## Variable-rotation test procedure

Run converge once with `awg_jc: 5` (the default in molecule.yml), then a second time with `awg_jc: 7`:

```bash
molecule converge
# edit molecule.yml group_vars awg_jc → 7
molecule converge
```

The second run must report `changed=1` (template task) and show the `Restart awg-quick@awg0` handler fired once (skipped in Docker due to `when: != docker` guard). No Xray or Hysteria2 tasks appear because this scenario applies only the `amneziawg` role.

## Known gaps

- DKMS source download, build (`dkms build`), install (`dkms install`), and autoinstall tasks all carry `when: ansible_virtualization_type != 'docker'` guards. In Docker, these tasks are skipped; `verify.yml` does not assert `lsmod` output or DKMS state.
- `awg-quick@awg0` service is only enabled/started on a real VPS. The systemd assertion in `verify.yml` is similarly guarded.
- `awg_tools_zip` is built for Ubuntu 22.04 (glibc). The same binary works on Debian 12 because both use compatible glibc versions. Alpine and musl-based systems are not supported.

## Images used

| Platform   | Image                                   |
| ---------- | --------------------------------------- |
| ubuntu2204 | `geerlingguy/docker-ubuntu2204-ansible` |
| debian12   | `geerlingguy/docker-debian12-ansible`   |

Both images ship with systemd stubs and `python3` pre-installed, which Ansible requires for `service_facts` and general module execution.

## DKMS build time note

Profile the `dkms build` step on real hardware. If it consistently exceeds 5 minutes, open a follow-up task to evaluate pre-built DKMS packages or a kernel module cache per FEAT-0001 (AC-2, ≤15 min total).

## How to run

```bash
cd ansible/roles/amneziawg
molecule test          # full lifecycle: create → prepare → converge → idempotence → verify → destroy
molecule converge      # apply role only (containers remain running)
molecule verify        # run verify.yml against running containers
molecule destroy       # tear down containers
```
