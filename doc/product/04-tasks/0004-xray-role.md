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

## Implementation Plan

This role has three distinct concerns: (1) binary installation, (2) config file templating, and (3) systemd service lifecycle management. The TDD sub-steps below address each in order, keeping concerns in separate files so reviewers can verify single-responsibility at every file boundary.

### Sub-step 1 — Write failing Molecule tests (TDD first)

Create `ansible/roles/xray/molecule/default/` before writing any task logic.

**`molecule/default/molecule.yml`** — declare the Docker driver with two platforms:

- `name: ubuntu2204`, image `geerlingguy/docker-ubuntu2204-ansible`, `privileged: true`
- `name: debian12`, image `geerlingguy/docker-debian12-ansible`, `privileged: true`

Set `provisioner.name: ansible` and `verifier.name: ansible`. Supply concrete variable overrides via `provisioner.inventory.group_vars.all` so every verify assertion has an exact expected value to compare against:

```yaml
xray_port: 10443
xray_uuid: "12345678-1234-1234-1234-123456789012"
xray_server_name: "www.example.com"
xray_private_key: "PLACEHOLDER_PRIVKEY"
xray_public_key: "PLACEHOLDER_PUBKEY"
xray_short_id: "aabbccdd"
```

**`molecule/default/prepare.yml`** — install `unzip` and `curl` via `ansible.builtin.apt` before the role runs, simulating what the `prerequisites` role provides. This is required because the scenario does not invoke the `prerequisites` role.

**`molecule/default/converge.yml`** — a minimal playbook that applies only the `xray` role, not the full `playbook.yml`, so the scenario is self-contained.

**`molecule/default/verify.yml`** — write `ansible.builtin.assert` tasks for the following cases (all must fail until the implementation in Sub-steps 2–4 is complete — that is the expected TDD red state):

1. `ansible.builtin.stat` on `/usr/local/bin/xray` — assert `stat.exists == true` and `stat.executable == true`.
2. `ansible.builtin.stat` on `/etc/xray/config.json` — assert `stat.exists == true` and `stat.mode == '0600'`.
3. `ansible.builtin.slurp` `/etc/xray/config.json`, base64-decode, assert the decoded string contains `"10443"` (the port), `"12345678-1234-1234-1234-123456789012"` (the UUID), and `"www.example.com"` (the serverName). These checks satisfy AC-5.
4. `ansible.builtin.stat` on `/etc/systemd/system/xray.service` — assert `stat.exists == true`.
5. `ansible.builtin.service_facts`, then assert `xray.service` is in `enabled` state. Skip `state: active` assertion with an inline comment: Docker containers may not have a fully initialised systemd; the `started` state is verified on a real VPS (AC-1 partial).

**`molecule/default/README.md`** — stub file to be completed in Sub-step 5.

At this point `molecule converge` must fail because `roles/xray/tasks/main.yml` does not exist. That is the expected TDD red state.

### Sub-step 2 — Implement binary installation in `roles/xray/tasks/install.yml`

Create `ansible/roles/xray/tasks/install.yml` (sourced via `include_tasks:` from `tasks/main.yml`). Single-responsibility: this file owns only the Xray binary and its directory prerequisites — no config templating, no service management.

**Role-internal version pin**

Create `ansible/roles/xray/vars/main.yml` with role-internal constants:

```yaml
xray_version: "1.8.11" # Update when upstream releases change binary paths or checksums.
xray_archive_sha256: "<sha256>" # SHA-256 of the release zip; update alongside xray_version.
```

These are role-internal constants, not operator-tunable variables. They belong in `roles/xray/vars/main.yml`, not `ansible/vars/main.yml`. Document the maintenance obligation in the role README (Sub-step 5): every upstream Xray release that changes the binary path, zip filename pattern, or systemd unit format requires updating `xray_version` and `xray_archive_sha256` here.

**Task: Create `/usr/local/bin/` and `/etc/xray/` directories**

Use `ansible.builtin.file` with `state: directory` for:

- `/usr/local/bin/` — `mode: '0755'`, `owner: root`
- `/etc/xray/` — `mode: '0750'`, `owner: root`, `group: root`

Both tasks are idempotent by nature.

**Task: Download Xray release archive**

Use `ansible.builtin.get_url` to fetch the release zip from `https://github.com/XTLS/Xray-core/releases/download/v{{ xray_version }}/Xray-linux-64.zip` to `/tmp/xray-{{ xray_version }}.zip`. Set:

- `checksum: sha256:{{ xray_archive_sha256 }}` — this makes the task report `ok` if the file is already present and the checksum matches, and re-download only if the file is missing or corrupt.
- `mode: '0644'`
- `owner: root`

Do not use `creates:` alone as the idempotency guard — `get_url` with `checksum:` is the correct mechanism here (per task Notes).

**Task: Extract `xray` binary from archive**

Use `ansible.builtin.unarchive` with:

- `src: /tmp/xray-{{ xray_version }}.zip`
- `dest: /usr/local/bin/`
- `include: [ "xray" ]`
- `remote_src: true`
- `creates: /usr/local/bin/xray`
- `mode: '0755'`
- `owner: root`

The `creates:` guard makes this idempotent — if `/usr/local/bin/xray` already exists (from a prior run), the task skips. This means a version upgrade requires manually removing the binary or changing the `creates:` guard to check version output. Flag this limitation in the role README and note that a version-check approach (e.g., `command: xray version | grep {{ xray_version }}` with `register` + `when`) can be added as a follow-up if upgrade idempotency becomes a requirement.

**Single-responsibility flag:** Do not install the `geoip.dat` or `geosite.dat` asset files in this file. Xray REALITY config does not require them. If they are ever needed, add a separate `assets.yml` task file and include it from `main.yml`.

### Sub-step 3 — Implement config templating in `roles/xray/tasks/config.yml` and `roles/xray/templates/config.json.j2`

Create `ansible/roles/xray/tasks/config.yml` (sourced via `include_tasks:` from `tasks/main.yml`). Single-responsibility: this file owns only the Xray JSON config — no binary installation, no service management.

**Task: Template `config.json`**

Use `ansible.builtin.template` with:

- `src: config.json.j2`
- `dest: /etc/xray/config.json`
- `mode: '0600'`
- `owner: root`
- `validate: /usr/local/bin/xray run -test -config %s`
- `notify: Restart xray`

The `validate:` field runs `xray run -test -config <tempfile>` before placing the rendered file, catching JSON syntax errors and Xray-level config validation errors before they can break a running service. The task only reports `changed` if the rendered output differs from the file on disk — this is the mechanism that satisfies AC-3 (idempotency) and AC-4 (variable-rotation triggers exactly one restart).

**Template `roles/xray/templates/config.json.j2` structure**

The template must render a VLESS+XTLS-Vision+REALITY inbound. Required variable references (all sourced from `ansible/vars/main.yml` via TASK-0001; no `| default(...)` filters — missing variables must cause a loud Jinja2 `UndefinedError`):

- Inbound `port`: `{{ xray_port | int }}`
- Inbound protocol: `"vless"`
- Client `id`: `{{ xray_uuid }}`
- Client `flow`: `"xtls-rprx-vision"`
- `streamSettings.security`: `"reality"`
- `streamSettings.realitySettings.dest`: `{{ xray_reality_dest }}` (the decoy destination; agreed in TASK-0001/TASK-0009 — use the variable name, not a hardcoded domain)
- `streamSettings.realitySettings.serverNames`: `[ "{{ xray_server_name }}" ]`
- `streamSettings.realitySettings.privateKey`: `{{ xray_private_key }}`
- `streamSettings.realitySettings.shortIds`: `[ "{{ xray_short_id }}" ]`
- Outbound `protocol`: `"freedom"`

**SOLID flag:** The template contains only rendering logic (variable substitution). It must not embed conditional protocol-selection logic (e.g., `{% if xray_protocol == "vless" %}`). This task covers only VLESS+XTLS-Vision+REALITY. If a second protocol variant is ever required, that is a new template and a new task, not a branch in this template.

### Sub-step 4 — Implement service management in `roles/xray/tasks/main.yml` and `roles/xray/handlers/main.yml`

`tasks/main.yml` is the role entry point. It orchestrates the three concerns via `include_tasks:` and owns the systemd unit installation and service lifecycle directly (these two actions are tightly coupled and do not warrant a separate sub-file).

**`include_tasks: install.yml`** — first, unconditionally.

**`include_tasks: config.yml`** — second, unconditionally.

**Task: Install systemd unit file**

Use `ansible.builtin.template` (not `ansible.builtin.copy`) for the systemd unit so that role-internal variables (e.g., `xray_version` for a `Description:` line) can be interpolated:

- `src: xray.service.j2`
- `dest: /etc/systemd/system/xray.service`
- `mode: '0644'`
- `owner: root`
- `notify: Restart xray`

Create `ansible/roles/xray/templates/xray.service.j2`. The unit must contain at minimum:

- `[Unit]` — `Description`, `After=network.target`
- `[Service]` — `ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json`, `Restart=on-failure`, `User=root`
- `[Install]` — `WantedBy=multi-user.target`

**Task: Reload systemd daemon**

Use `ansible.builtin.systemd` with `daemon_reload: true` immediately after the unit file task. Use `listen: Reload systemd` and trigger it only when the unit file changes (via `notify: Reload systemd` on the unit file task), rather than running `daemon_reload` unconditionally on every play. This avoids an unnecessary syscall on idempotent runs.

**Task: Enable and start `xray.service`**

Use `ansible.builtin.systemd` with:

- `name: xray`
- `enabled: true`
- `state: started`

Do not set `daemon_reload: true` here — it already fired via the handler above. Apply `when: ansible_virtualization_type != 'docker'` because Docker containers may not have a fully functional systemd. Document the guard inline referencing AC-1.

**Handler: `Restart xray`**

Create `ansible/roles/xray/handlers/main.yml` with a single handler:

```yaml
- name: Restart xray
  ansible.builtin.systemd:
    name: xray
    state: restarted
  when: ansible_virtualization_type != 'docker'
```

This is the only handler in this role. The name must match the string passed to `notify:` in the config template task exactly. The `when:` guard prevents Docker failures without suppressing real-VPS restarts (AC-4). Do not add `daemon_reload: true` to the handler — the unit file is not changing when the config changes, so reloading the daemon here is unnecessary and masks intent.

**SOLID flag:** The handler file contains exactly one handler. If a future task needs to restart a dependent service after an Xray restart (e.g., a monitoring sidecar), that handler belongs in that service's role, not here.

### Sub-step 5 — Author `molecule/default/README.md` and complete the scenario

**`molecule/default/README.md`** must include:

- **ACs exercised in this scenario:**
  - AC-3 (idempotency) — Molecule's built-in second-converge check asserts `changed=0`.
  - AC-4 (variable-rotation) — A third converge with `xray_port` changed to a different value must report `changed=1` (config template task only) and trigger the `Restart xray` handler exactly once; the `amneziawg` and `hysteria2` roles are not in scope for this scenario and cannot be accidentally restarted.
  - AC-5 (config contents) — `verify.yml` asserts port, UUID, and serverName appear verbatim in the rendered `/etc/xray/config.json`.
  - AC-11 (scenario passes in CI) — `make test` includes this scenario.
- **ACs not exercised in Docker (with explanation):**
  - AC-1 (`systemctl is-active xray`): Docker may not have a working systemd. The `state: started` task is guarded with `when: ansible_virtualization_type != 'docker'`. Manual checklist: SSH to real VPS after `make deploy`, run `systemctl is-active xray` — must return exit code 0.
  - AC-2 (deploy time ≤ 15 min): Binary download speed depends on real network conditions. Docker I/O does not reflect a real VPS. No timing assertion is included.
- **Variable-rotation test procedure:** Run `molecule converge` twice — once with `xray_port: 10443` and once with `xray_port: 10444`. The second run must report `changed=1` and show the handler firing. No AmneziaWG or Hysteria2 tasks should appear in the output.
- **How to run:** `cd ansible && molecule test -s default` (full cycle including idempotency check).
- **Maintenance note:** `xray_version` and `xray_archive_sha256` in `roles/xray/vars/main.yml` must be updated for every upstream Xray release. The Molecule scenario pins concrete values and will catch a checksum mismatch on `molecule converge`.

### Sub-step 6 — Wire role into `playbook.yml` and verify ordering

Confirm that `ansible/playbook.yml` lists `xray` as the third role (after `prerequisites` and `amneziawg`, before `hysteria2`). This ordering was established in TASK-0001. If the file still uses stubs, update only the `xray` entry position — no other changes to `playbook.yml` are in scope.

Run `molecule test` (both platforms) to confirm:

1. `verify.yml` assertions pass for binary presence, config file mode, config contents (AC-5), and service-enabled state.
2. Molecule's built-in idempotency check (second converge) reports `changed=0` — AC-3 satisfied.
3. Third converge with `xray_port` changed reports `changed=1` (template task) and handler fires exactly once — AC-4 satisfied.
4. No AmneziaWG or Hysteria2 handler names appear in the task output.

## Edge Cases

The following edge cases are derived directly from the feature's acceptance criteria and the notes above.

| Edge case                                                                                                                                                                                                | Source AC              | How this task addresses it                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `get_url` with `checksum:` re-downloads the archive on every run if `/tmp/xray-{{ xray_version }}.zip` is cleaned between runs (e.g., by OS tmp-cleanup timers) but `/usr/local/bin/xray` already exists | AC-3                   | The `unarchive` task's `creates: /usr/local/bin/xray` guard prevents re-extraction even if the archive is re-downloaded. The net result is `changed=0` for the extract step. Document this two-step guard pattern in `install.yml` inline comments.                                                |
| `xray_private_key` or `xray_public_key` is missing from the variable set (FEAT-0002 SOPS decrypt was skipped)                                                                                            | AC-5                   | The template uses bare variable references with no `\| default(...)`. Jinja2 raises `UndefinedError` and the template task fails loudly before writing any file. This is the correct behaviour — a missing secret must be an explicit failure, not a silently broken config.                       |
| `xray run -test -config` validation in `validate:` fails if Xray binary is not yet installed when the config task runs                                                                                   | AC-1                   | `tasks/main.yml` includes `install.yml` before `config.yml`. The ordering is unconditional and must not be changed. Add an inline comment in `main.yml` flagging the dependency.                                                                                                                   |
| Changing only `xray_server_name` must restart Xray but must not restart Hysteria2 or AmneziaWG                                                                                                           | AC-4                   | The `notify: Restart xray` is on the `ansible.builtin.template` task in `config.yml`. The handler is defined exclusively in `roles/xray/handlers/main.yml`. No other role references this handler name. Verify by grepping the codebase for `Restart xray` — it must appear only in `roles/xray/`. |
| Systemd `daemon_reload` must fire when the unit file changes but not on every play                                                                                                                       | AC-3                   | The `xray.service.j2` template task notifies a `Reload systemd` handler (not the `Restart xray` handler). The `Restart xray` handler is notified only by the config template task. These are two separate notification paths — do not merge them.                                                  |
| `config.json` rendered with `mode: '0600'` ensures Xray does not expose secrets to other OS users                                                                                                        | AC-5                   | The `ansible.builtin.template` task sets `mode: '0600'` explicitly. The Molecule `verify.yml` asserts `stat.mode == '0600'` to catch any regression. Do not rely on `umask` defaults.                                                                                                              |
| Xray binary version upgrade: `creates: /usr/local/bin/xray` prevents re-extraction when the binary already exists, so bumping `xray_version` alone does not replace the binary                           | Maintenance obligation | Document in role README: to upgrade the binary, either remove `/usr/local/bin/xray` on the target before re-running, or add a version-check task (e.g., compare `xray version` output against `xray_version`) in a follow-up task. Scope of this task is the initial install only.                 |
