---
id: TASK-0005
status: todo
feature_id: FEAT-0001
---

## Description

An idempotent `hysteria2` Ansible role downloads the Hysteria2 binary, writes a config from a Jinja2 template, and manages a systemd service unit. After this task, `systemctl is-active hysteria2` returns exit code 0 on a fresh VPS, the deployed config reflects `vars/main.yml` values, and only Hysteria2-variable changes trigger a Hysteria2 restart.

Done looks like:

- `roles/hysteria2/tasks/main.yml` downloads the Hysteria2 binary (pinned version) to `/usr/local/bin/hysteria2`, verifies its checksum, and installs a systemd unit at `/etc/systemd/system/hysteria2.service`.
- `roles/hysteria2/templates/config.yaml.j2` produces a valid Hysteria2 YAML config using `hysteria2_port` and `hysteria2_obfs_password` from `vars/main.yml`.
- The systemd service is enabled and started.
- Re-running with no variable changes produces `changed=0` and does not restart Hysteria2.
- Changing `hysteria2_port` and re-running restarts Hysteria2 exactly once via a handler; Xray and AmneziaWG are not restarted.
- A Molecule scenario verifies: binary present and executable, config file contents match template variables (AC-5), service active (AC-1 partial), idempotency (AC-3), and variable-rotation restarts only Hysteria2 (AC-4).

## Notes

- Depends on TASK-0001 (vars schema) and TASK-0002 (prerequisites installed).
- Pin the Hysteria2 version in `vars/main.yml`. Upstream binary path or unit name changes are a known maintenance risk (see feature Consequences); document in role README.
- Use `ansible.builtin.get_url` with `checksum:` for idempotent binary download.
- Hysteria2 requires a TLS certificate; the certificate path variable must be declared in TASK-0001's vars schema. The role writes the cert from a variable but does not generate it — cert generation is out of scope for this task.
- Handler `Restart hysteria2` must be scoped to this role only.
