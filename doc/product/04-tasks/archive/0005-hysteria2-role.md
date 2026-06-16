---
id: TASK-0005
status: done
feature_id: FEAT-0001
completed_at: "2026-06-16T11:06:08.115Z"
commit_sha: 954ef583e9cc5c65deda88def98ef262c1e28324
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

## Implementation Plan

This role has three distinct concerns: (1) binary installation, (2) config file templating (including TLS cert placement), and (3) systemd service lifecycle management. The TDD sub-steps below address each in order, keeping concerns in separate files so reviewers can verify single-responsibility at every file boundary.

### Sub-step 1 — Write failing Molecule tests (TDD first)

Create `ansible/roles/hysteria2/molecule/default/` before writing any task logic.

**`molecule/default/molecule.yml`** — declare the Docker driver with two platforms:

- `name: ubuntu2204`, image `geerlingguy/docker-ubuntu2204-ansible`, `privileged: true`
- `name: debian12`, image `geerlingguy/docker-debian12-ansible`, `privileged: true`

Set `provisioner.name: ansible` and `verifier.name: ansible`. Supply concrete variable overrides via `provisioner.inventory.group_vars.all` so every verify assertion has an exact expected value to compare against:

```yaml
hysteria2_port: 10443
hysteria2_obfs_password: "test-obfs-password"
hysteria2_tls_cert: "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0t" # base64 placeholder; real cert injected by FEAT-0002
hysteria2_tls_key: "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0t" # base64 placeholder
```

**`molecule/default/prepare.yml`** — install `curl` via `ansible.builtin.apt` before the role runs, simulating what the `prerequisites` role provides. This is required because the scenario does not invoke the `prerequisites` role.

**`molecule/default/converge.yml`** — a minimal playbook that applies only the `hysteria2` role, not the full `playbook.yml`, so the scenario is self-contained.

**`molecule/default/verify.yml`** — write `ansible.builtin.assert` tasks for the following cases (all must fail until the implementation in Sub-steps 2–4 is complete — that is the expected TDD red state):

1. `ansible.builtin.stat` on `/usr/local/bin/hysteria2` — assert `stat.exists == true` and `stat.executable == true`.
2. `ansible.builtin.stat` on `/etc/hysteria2/config.yaml` — assert `stat.exists == true` and `stat.mode == '0600'`.
3. `ansible.builtin.slurp` `/etc/hysteria2/config.yaml`, base64-decode, assert the decoded string contains `"10443"` (the port) and `"test-obfs-password"` (the obfs password). These checks satisfy AC-5.
4. `ansible.builtin.stat` on `/etc/hysteria2/server.crt` — assert `stat.exists == true` and `stat.mode == '0600'`.
5. `ansible.builtin.stat` on `/etc/systemd/system/hysteria2.service` — assert `stat.exists == true`.
6. `ansible.builtin.service_facts`, then assert `hysteria2.service` is in `enabled` state. Skip `state: active` assertion with an inline comment: Docker containers may not have a fully initialised systemd; the `started` state is verified on a real VPS (AC-1 partial).

**`molecule/default/README.md`** — stub file to be completed in Sub-step 5.

At this point `molecule converge` must fail because `roles/hysteria2/tasks/main.yml` does not exist. That is the expected TDD red state.

### Sub-step 2 — Implement binary installation in `roles/hysteria2/tasks/install.yml`

Create `ansible/roles/hysteria2/tasks/install.yml` (sourced via `include_tasks:` from `tasks/main.yml`). Single-responsibility: this file owns only the Hysteria2 binary and its directory prerequisites — no config templating, no service management.

**Role-internal version pin**

Create `ansible/roles/hysteria2/vars/main.yml` with role-internal constants:

```yaml
hysteria2_version: "2.6.1" # Update when upstream releases change binary paths or checksums.
hysteria2_binary_sha256: "<sha256>" # SHA-256 of the release binary; update alongside hysteria2_version.
```

These are role-internal constants, not operator-tunable variables. They belong in `roles/hysteria2/vars/main.yml`, not `ansible/vars/main.yml`. The Hysteria2 upstream releases a single pre-built binary (not a zip archive), so `ansible.builtin.get_url` downloads directly to `/usr/local/bin/hysteria2` — no `unarchive` step is needed. Document the maintenance obligation in the role README (Sub-step 5): every upstream Hysteria2 release that changes the binary path, release filename pattern, or systemd unit format requires updating `hysteria2_version` and `hysteria2_binary_sha256` here.

**Task: Create `/usr/local/bin/` and `/etc/hysteria2/` directories**

Use `ansible.builtin.file` with `state: directory` for:

- `/usr/local/bin/` — `mode: '0755'`, `owner: root`
- `/etc/hysteria2/` — `mode: '0750'`, `owner: root`, `group: root`

Both tasks are idempotent by nature.

**Task: Download Hysteria2 binary**

Use `ansible.builtin.get_url` to fetch the binary directly from `https://github.com/apernet/hysteria/releases/download/app/v{{ hysteria2_version }}/hysteria-linux-amd64` to `/usr/local/bin/hysteria2`. Set:

- `checksum: sha256:{{ hysteria2_binary_sha256 }}` — this makes the task report `ok` if the file is already present and the checksum matches, and re-download only if the file is missing or corrupt.
- `mode: '0755'`
- `owner: root`

Using `get_url` with `checksum:` is the correct idempotency mechanism here (per task Notes). Unlike the Xray role, there is no intermediate archive or `unarchive` step — the binary is downloaded directly. The `checksum:` guard means the task will report `changed` only on the first run or after a manual file deletion. A version upgrade requires updating `hysteria2_binary_sha256` in `roles/hysteria2/vars/main.yml`; the changed checksum will cause `get_url` to re-download and overwrite the binary automatically.

**Single-responsibility flag:** Do not install or validate the TLS certificate in this file. Certificate placement is a separate concern handled in `config.yml` (Sub-step 3).

### Sub-step 3 — Implement config templating in `roles/hysteria2/tasks/config.yml` and `roles/hysteria2/templates/config.yaml.j2`

Create `ansible/roles/hysteria2/tasks/config.yml` (sourced via `include_tasks:` from `tasks/main.yml`). Single-responsibility: this file owns the Hysteria2 YAML config and TLS certificate placement — no binary installation, no service management.

**Task: Write TLS certificate file**

Use `ansible.builtin.copy` with:

- `content: "{{ hysteria2_tls_cert | b64decode }}"` — the cert is stored base64-encoded in the vars file (injected by FEAT-0002 via SOPS), decoded here at write time.
- `dest: /etc/hysteria2/server.crt`
- `mode: '0600'`
- `owner: root`
- `notify: Restart hysteria2`

**Task: Write TLS private key file**

Use `ansible.builtin.copy` with:

- `content: "{{ hysteria2_tls_key | b64decode }}"`
- `dest: /etc/hysteria2/server.key`
- `mode: '0600'`
- `owner: root`
- `notify: Restart hysteria2`

**Task: Template `config.yaml`**

Use `ansible.builtin.template` with:

- `src: config.yaml.j2`
- `dest: /etc/hysteria2/config.yaml`
- `mode: '0600'`
- `owner: root`
- `notify: Restart hysteria2`

Do not use a `validate:` field here. Unlike Xray, the Hysteria2 binary does not expose a `--test` or `run -test` flag suitable for pre-flight config validation in Ansible's temp-file model. Omitting `validate:` is the correct choice; document this in an inline comment in `config.yml`.

The task only reports `changed` if the rendered output differs from the file on disk — this is the mechanism that satisfies AC-3 (idempotency) and AC-4 (variable-rotation triggers exactly one restart).

**Template `roles/hysteria2/templates/config.yaml.j2` structure**

The template must render a valid Hysteria2 server YAML config. Required variable references (all sourced from `ansible/vars/main.yml` via TASK-0001; no `| default(...)` filters — missing variables must cause a loud Jinja2 `UndefinedError`):

```yaml
listen: ":{{ hysteria2_port | int }}"

tls:
  cert: /etc/hysteria2/server.crt
  key: /etc/hysteria2/server.key

obfs:
  type: salamander
  salamander:
    password: "{{ hysteria2_obfs_password }}"

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520

bandwidth:
  up: 1 gbps
  down: 1 gbps
```

The `listen`, `obfs.salamander.password`, and `tls.cert`/`tls.key` paths are the variable-driven fields. The `quic` and `bandwidth` blocks use safe static defaults that do not require operator tuning; they are not parameterised here (YAGNI — add variables only if a future task explicitly requires tuning them).

**SOLID flag:** The template contains only rendering logic (variable substitution and static defaults). It must not embed conditional protocol-selection logic. This task covers Hysteria2 with Salamander obfuscation only. If a second obfuscation variant or authentication method is ever required, that is a new template and a new task, not a branch in this template.

### Sub-step 4 — Implement service management in `roles/hysteria2/tasks/main.yml` and `roles/hysteria2/handlers/main.yml`

`tasks/main.yml` is the role entry point. It orchestrates the three concerns via `include_tasks:` and owns the systemd unit installation and service lifecycle directly (these two actions are tightly coupled and do not warrant a separate sub-file).

**`include_tasks: install.yml`** — first, unconditionally.

**`include_tasks: config.yml`** — second, unconditionally. An inline comment must flag that this ordering is a hard dependency: the Hysteria2 binary must exist before the config template task runs, because `config.yml` tasks notify `Restart hysteria2` and the handler invokes `systemd`, which in turn needs the binary to start the service.

**Task: Install systemd unit file**

Use `ansible.builtin.template` (not `ansible.builtin.copy`) for the systemd unit so that role-internal variables (e.g., `hysteria2_version` for a `Description:` line) can be interpolated:

- `src: hysteria2.service.j2`
- `dest: /etc/systemd/system/hysteria2.service`
- `mode: '0644'`
- `owner: root`
- `notify: Reload systemd daemon`

Create `ansible/roles/hysteria2/templates/hysteria2.service.j2`. The unit must contain at minimum:

- `[Unit]` — `Description: Hysteria2 proxy server v{{ hysteria2_version }}`, `After=network.target`
- `[Service]` — `ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.yaml`, `Restart=on-failure`, `User=root`
- `[Install]` — `WantedBy=multi-user.target`

Note: Hysteria2 uses the subcommand `server` (not `run`). This differs from Xray's invocation — do not copy the Xray unit template without changing this.

**Task: Reload systemd daemon**

Use `ansible.builtin.systemd` with `daemon_reload: true` in a handler named `Reload systemd daemon`. Notify it from the unit file task above (not from the config template tasks). This avoids an unnecessary daemon reload on idempotent runs where only the config changes.

**Task: Enable and start `hysteria2.service`**

Use `ansible.builtin.systemd` with:

- `name: hysteria2`
- `enabled: true`
- `state: started`

Apply `when: ansible_virtualization_type != 'docker'` because Docker containers may not have a fully functional systemd. Document the guard inline referencing AC-1.

**Handler: `Restart hysteria2`**

Create `ansible/roles/hysteria2/handlers/main.yml` with two handlers:

```yaml
- name: Restart hysteria2
  ansible.builtin.systemd:
    name: hysteria2
    state: restarted
  when: ansible_virtualization_type != 'docker'

- name: Reload systemd daemon
  ansible.builtin.systemd:
    daemon_reload: true
  when: ansible_virtualization_type != 'docker'
```

`Restart hysteria2` is the only handler notified by `config.yml` tasks. `Reload systemd daemon` is notified only by the unit file task in `main.yml`. The two handler names must match their `notify:` strings exactly. Do not define a handler named `Restart xray`, `Restart amneziawg`, or any name belonging to another role — name collisions across roles cause incorrect cross-role restarts.

**SOLID flag:** The handler file contains exactly two handlers, each with a single distinct responsibility. If a future task needs to restart a dependent service after a Hysteria2 restart, that handler belongs in that service's role, not here.

### Sub-step 5 — Author `molecule/default/README.md` and complete the scenario

**`molecule/default/README.md`** must include:

- **ACs exercised in this scenario:**
  - AC-3 (idempotency) — Molecule's built-in second-converge check asserts `changed=0`.
  - AC-4 (variable-rotation) — A third converge with `hysteria2_port` changed to a different value must report `changed=1` (config template task only) and trigger the `Restart hysteria2` handler exactly once; the `xray` and `amneziawg` roles are not in scope for this scenario and cannot be accidentally restarted.
  - AC-5 (config contents) — `verify.yml` asserts port and obfs password appear verbatim in the rendered `/etc/hysteria2/config.yaml`.
  - AC-11 (scenario passes in CI) — `make test` includes this scenario.
- **ACs not exercised in Docker (with explanation):**
  - AC-1 (`systemctl is-active hysteria2`): Docker may not have a working systemd. The `state: started` task is guarded with `when: ansible_virtualization_type != 'docker'`. Manual checklist: SSH to real VPS after `make deploy`, run `systemctl is-active hysteria2` — must return exit code 0.
  - AC-2 (deploy time ≤ 15 min): Binary download speed depends on real network conditions. Docker I/O does not reflect a real VPS. No timing assertion is included.
- **Variable-rotation test procedure:** Run `molecule converge` twice — once with `hysteria2_port: 10443` and once with `hysteria2_port: 10444`. The second run must report `changed=1` and show the handler firing. No Xray or AmneziaWG tasks should appear in the output.
- **How to run:** `cd ansible && molecule test -s default` (full cycle including idempotency check).
- **Maintenance note:** `hysteria2_version` and `hysteria2_binary_sha256` in `roles/hysteria2/vars/main.yml` must be updated for every upstream Hysteria2 release. Unlike the Xray role, the changed checksum causes `get_url` to automatically re-download and overwrite the binary — no manual file removal is needed for version upgrades.

### Sub-step 6 — Wire role into `playbook.yml` and verify ordering

Confirm that `ansible/playbook.yml` lists `hysteria2` as the fourth role (after `prerequisites`, `amneziawg`, and `xray`, before `firewall`). This ordering was established in TASK-0001. If the file still uses stubs, update only the `hysteria2` entry position — no other changes to `playbook.yml` are in scope.

Run `molecule test` (both platforms) to confirm:

1. `verify.yml` assertions pass for binary presence, config file mode, config contents (AC-5), cert file presence, and service-enabled state.
2. Molecule's built-in idempotency check (second converge) reports `changed=0` — AC-3 satisfied.
3. Third converge with `hysteria2_port` changed reports `changed=1` (template task) and handler fires exactly once — AC-4 satisfied.
4. No Xray or AmneziaWG handler names appear in the task output.

## Edge Cases

The following edge cases are derived directly from the feature's acceptance criteria and the notes above.

| Edge case                                                                                                                                                   | Source AC | How this task addresses it                                                                                                                                                                                                                                                                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hysteria2_tls_cert` or `hysteria2_tls_key` is missing from the variable set (FEAT-0002 SOPS decrypt was skipped)                                           | AC-5      | The `copy` tasks in `config.yml` use bare variable references with no `\| default(...)`. Jinja2 raises `UndefinedError` and the task fails loudly before writing any file. A missing TLS secret must be an explicit failure, not a silently broken config.                                                                                                                                               |
| `hysteria2_obfs_password` is missing from the variable set                                                                                                  | AC-5      | The template uses a bare `{{ hysteria2_obfs_password }}` reference with no `\| default(...)`. Jinja2 raises `UndefinedError`. Same pattern as above.                                                                                                                                                                                                                                                     |
| Hysteria2 binary listens on UDP, not TCP — the firewall role must open a UDP port, not a TCP port                                                           | AC-6      | This role does not manage the firewall. Document in the role README that `hysteria2_port` must be opened as UDP in the `firewall` role (TASK-0006). Flag this coupling explicitly so the firewall role author does not default to TCP.                                                                                                                                                                   |
| Changing only `hysteria2_obfs_password` must restart Hysteria2 but must not restart Xray or AmneziaWG                                                       | AC-4      | The `notify: Restart hysteria2` is on the `ansible.builtin.template` task in `config.yml`. The handler is defined exclusively in `roles/hysteria2/handlers/main.yml`. Verify by grepping the codebase for `Restart hysteria2` — it must appear only in `roles/hysteria2/`.                                                                                                                               |
| Changing `hysteria2_tls_cert` must restart Hysteria2                                                                                                        | AC-4      | The `ansible.builtin.copy` task for the cert file in `config.yml` also carries `notify: Restart hysteria2`. A cert rotation therefore triggers exactly one restart via the same handler, consistent with the port-change case.                                                                                                                                                                           |
| Systemd `daemon_reload` must fire when the unit file changes but not when only the config or cert changes                                                   | AC-3      | The unit file task notifies `Reload systemd daemon`; the config and cert tasks notify only `Restart hysteria2`. These are two separate notification paths — do not merge them. A config-only change produces one handler invocation (`Restart hysteria2`), not two.                                                                                                                                      |
| `/etc/hysteria2/config.yaml` rendered with `mode: '0600'` protects the obfs password from other OS users                                                    | AC-5      | The `ansible.builtin.template` task sets `mode: '0600'` explicitly. The Molecule `verify.yml` asserts `stat.mode == '0600'` to catch any regression. Do not rely on `umask` defaults.                                                                                                                                                                                                                    |
| TLS cert and key files rendered with `mode: '0600'` prevent private key exposure                                                                            | AC-5      | Both `ansible.builtin.copy` tasks in `config.yml` set `mode: '0600'` explicitly. The Molecule `verify.yml` asserts this on `server.crt`; add the same assertion for `server.key`.                                                                                                                                                                                                                        |
| `get_url` with `checksum:` re-downloads the binary if it is corrupt or missing, but overwrites the running binary if Hysteria2 is active at deploy time     | AC-3      | Hysteria2 is a single statically-linked binary; Linux allows overwriting an open executable — the running process continues using the old inode until it exits. The service will pick up the new binary on the next restart. No special handling is needed; document this behaviour in `install.yml` inline comments.                                                                                    |
| The Hysteria2 `server` subcommand differs from Xray's invocation — using `run` instead of `server` in the unit file will cause the service to fail silently | AC-1      | The `hysteria2.service.j2` template must use `ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.yaml`. Add an inline comment in the template flagging the subcommand difference from Xray. The Molecule verify step's `service_facts` enabled-state check does not catch a bad `ExecStart` — document that `systemctl status hysteria2` on a real VPS is the authoritative check. |
