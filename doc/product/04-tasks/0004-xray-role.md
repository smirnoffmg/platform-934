---
id: TASK-0004
status: todo
feature_id: FEAT-0001
---

## Description

An idempotent `xray` Ansible role downloads the Xray binary, writes a VLESS+XTLS-Vision+REALITY config from a Jinja2 template, and manages a systemd service unit. After this task, `systemctl is-active xray` returns exit code 0 on a fresh VPS, deployed config files contain the exact values from `vars/main.yml`, and only an Xray-variable change causes an Xray restart.

Done looks like:

- `roles/xray/tasks/main.yml` downloads the Xray binary (pinned version) to `/usr/local/bin/xray`, verifies its checksum, and installs a systemd unit at `/etc/systemd/system/xray.service`.
- `roles/xray/templates/config.json.j2` produces a valid Xray VLESS+XTLS-Vision+REALITY JSON config using `xray_port`, `xray_uuid`, and `xray_server_name` from `vars/main.yml`.
- The systemd service is enabled and started.
- Re-running with no variable changes produces `changed=0` and does not restart Xray.
- Changing `xray_port` and re-running restarts Xray exactly once via a handler; Hysteria2 and AmneziaWG are not restarted.
- A Molecule scenario verifies: binary present and executable, config file contents match template variables (AC-5), service active (AC-1 partial), idempotency (AC-3), and variable-rotation restarts only Xray (AC-4).

## Notes

- Depends on TASK-0001 (vars schema) and TASK-0002 (prerequisites installed).
- Pin the Xray version in `vars/main.yml` (e.g., `xray_version: "1.8.x"`). The role must be updated when upstream releases change binary paths or service unit formats — document this as an ongoing maintenance obligation in the role README.
- Use `ansible.builtin.get_url` with `checksum:` to make the download idempotent (re-download only if the file is missing or corrupt).
- The handler `Restart xray` must only be notified by tasks in this role. Do not notify it from the firewall or prerequisites roles.
- REALITY requires a valid `privateKey` / `publicKey` pair; these are secrets injected by FEAT-0002. The template must reference the variable names agreed in TASK-0001 without embedding defaults.
