---
id: TASK-0003
status: todo
feature_id: FEAT-0001
---

## Description

An idempotent `amneziawg` Ansible role builds and installs the AmneziaWG kernel module via DKMS, installs the `awg` userspace tool, writes a WireGuard interface config from the vars template, and enables the interface at boot. After this task, a VPS can be rebooted and `lsmod | grep amneziawg` returns exit code 0 without manual intervention.

Done looks like:

- `roles/amneziawg/tasks/main.yml` clones or downloads the AmneziaWG source, registers it with DKMS, builds and installs the module for the running kernel, and runs `dkms autoinstall` hooks so the module rebuilds on kernel upgrade.
- A templated WireGuard interface config is written to `/etc/amneziawg/awg0.conf` using `awg_jc`, `awg_jmin`, `awg_jmax`, and `awg_port` from `vars/main.yml`.
- The `awg-quick@awg0` systemd service (or equivalent) is enabled and started.
- Re-running the role with no variable changes produces `changed=0`.
- Re-running after changing `awg_jc` restarts `awg-quick@awg0` exactly once via an Ansible handler; Xray and Hysteria2 are not restarted.
- A Molecule scenario (Docker driver) tests: package and source installation, config file contents matching variables, idempotency (AC-3), and variable-rotation idempotency (AC-4). The scenario documents that `lsmod` assertions are skipped in Docker and must be verified on a real VPS (AC-1, AC-8).

## Notes

- Depends on TASK-0001 (vars schema) and TASK-0002 (DKMS package present).
- DKMS module build is the highest-risk step for AC-2 (≤15 min). Profile it during real-VPS testing; note in role README that pre-built packages should be considered if build time consistently exceeds 5 minutes.
- Use `ansible.builtin.command` with `creates:` guards or `ansible.builtin.stat` checks to make DKMS registration and build steps idempotent — DKMS commands are not natively idempotent Ansible modules.
- The handler that restarts `awg-quick@awg0` must be scoped to this role only. Do not use `meta: flush_handlers` globally in the playbook, as that would trigger handlers from other roles prematurely.
- AmneziaWG DKMS hook persistence (AC-8) cannot be tested in Docker; document this explicitly in the Molecule scenario README and add a manual real-VPS test checklist item.
