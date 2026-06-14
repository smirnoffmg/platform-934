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

## Implementation Plan

This role has four distinct concerns: (1) DKMS source acquisition and module build, (2) `awg` userspace tool installation, (3) interface config templating, and (4) systemd service lifecycle management. The TDD sub-steps below address each in sequence, keeping concerns separate so that a reviewer can verify single-responsibility at each file boundary.

### Sub-step 1 — Write failing Molecule tests (TDD first)

Create `ansible/roles/amneziawg/molecule/default/` before writing any task logic.

**`molecule/default/molecule.yml`** — declare the Docker driver with two platforms:

- `name: ubuntu2204`, image `geerlingguy/docker-ubuntu2204-ansible`, `privileged: true`
- `name: debian12`, image `geerlingguy/docker-debian12-ansible`, `privileged: true`

Set `provisioner.name: ansible` and `verifier.name: ansible`. Pass variable overrides via `provisioner.inventory.group_vars.all` so the scenario exercises a concrete set of values:

```yaml
awg_port: 51820
awg_jc: 5
awg_jmin: 40
awg_jmax: 70
awg_private_key: "PLACEHOLDER_PRIVKEY"
awg_preshared_key: "PLACEHOLDER_PSK"
awg_client_public_key: "PLACEHOLDER_CPUBKEY"
awg_client_allowed_ips: "10.8.0.2/32"
awg_address: "10.8.0.1/24"
```

**`molecule/default/verify.yml`** — write `ansible.builtin.assert` tasks that must pass after converge. Specific assertions to include:

1. `ansible.builtin.stat` on `/etc/amneziawg/awg0.conf` — assert `stat.exists == true` and `stat.mode == '0600'`.
2. `ansible.builtin.slurp` `/etc/amneziawg/awg0.conf`, base64-decode, assert the decoded string contains `ListenPort = 51820`, `Jc = 5`, `Jmin = 40`, `Jmax = 70`.
3. `ansible.builtin.systemd` lookup via `ansible.builtin.service_facts` — assert `awg-quick@awg0.service` is `enabled` (skip `state: active` assertion in Docker because `awg-quick` requires a real kernel module; add an explicit comment referencing AC-1/AC-8).
4. `ansible.builtin.stat` on `/usr/bin/awg` — assert `stat.exists == true` and `stat.executable == true`.

Add a comment block in `verify.yml`:

```yaml
# lsmod assertions are intentionally absent.
# Docker containers share the host kernel; DKMS build and module load
# cannot be tested in this environment (AC-1, AC-8).
# Real-VPS manual checklist: run `lsmod | grep amneziawg` after reboot.
```

**`molecule/default/converge.yml`** — a minimal playbook that applies only the `amneziawg` role (not the full `playbook.yml`) so the scenario is self-contained and does not require prerequisite roles to be present in Docker.

**`molecule/default/prepare.yml`** — install `dkms`, `curl`, and `unzip` via `ansible.builtin.apt` on the Docker container before the role runs, simulating what the `prerequisites` role delivers. This is required because the scenario does not invoke the `prerequisites` role.

**`molecule/default/README.md`** — stub file to be completed in Sub-step 5.

At this point `molecule converge` must fail because `roles/amneziawg/tasks/main.yml` does not exist. That is the expected TDD red state.

### Sub-step 2 — Implement DKMS source acquisition and module build in `roles/amneziawg/tasks/dkms.yml`

Create `ansible/roles/amneziawg/tasks/dkms.yml` (sourced via `include_tasks:` from `tasks/main.yml`) with the following tasks. Single-responsibility: this file owns only the DKMS lifecycle — no config templating or service management.

**Task: Set AmneziaWG version fact**

Set `awg_version` from `roles/amneziawg/vars/main.yml` (e.g. `awg_version: "1.0.0"`). This pin prevents silent upstream breakage on re-runs. The version string is used in the DKMS source directory path and the `dkms.conf` `PACKAGE_VERSION` field.

**Task: Download AmneziaWG source archive**

Use `ansible.builtin.get_url` to fetch the release tarball from the AmneziaWG GitHub releases URL to `/usr/src/amneziawg-{{ awg_version }}.tar.gz`. Set `creates: /usr/src/amneziawg-{{ awg_version }}/dkms.conf` as the idempotency guard (not `creates:` on the tarball — the tarball itself is not the idempotency signal; the unpacked source directory is).

**Task: Unpack source archive**

Use `ansible.builtin.unarchive` with `src: /usr/src/amneziawg-{{ awg_version }}.tar.gz`, `dest: /usr/src/`, `remote_src: true`, and `creates: /usr/src/amneziawg-{{ awg_version }}/dkms.conf`. The `creates:` guard makes this idempotent — if the directory already exists from a prior run, the task reports `ok`.

**Task: Register module with DKMS**

Use `ansible.builtin.command` to run `dkms add -m amneziawg -v {{ awg_version }}`. Guard with:

```yaml
args:
  creates: /var/lib/dkms/amneziawg/{{ awg_version }}
```

`/var/lib/dkms/amneziawg/{{ awg_version }}` is created by `dkms add` and serves as the idempotency marker. If it already exists, `creates:` causes the task to skip without re-running `dkms add` (which would otherwise exit non-zero because the module is already registered).

**Task: Build module with DKMS**

Use `ansible.builtin.command` to run `dkms build -m amneziawg -v {{ awg_version }} -k {{ ansible_kernel }}`. Guard with:

```yaml
args:
  creates: /var/lib/dkms/amneziawg/{{ awg_version }}/{{ ansible_kernel }}/x86_64/module/amneziawg.ko
```

The `.ko` file path is the correct idempotency marker — it is only written after a successful build. On Docker, `ansible_kernel` resolves to the host kernel string, but `linux-headers-{{ ansible_kernel }}` will not be present; this task must be wrapped with:

```yaml
when: ansible_virtualization_type != 'docker'
```

Document the guard inline and in the README.

**Task: Install module with DKMS**

Use `ansible.builtin.command` to run `dkms install -m amneziawg -v {{ awg_version }} -k {{ ansible_kernel }}`. Guard with `creates:` pointing to `/lib/modules/{{ ansible_kernel }}/updates/dkms/amneziawg.ko`. Apply the same `when: ansible_virtualization_type != 'docker'` guard as the build task.

**Task: Enable DKMS autoinstall hook**

Use `ansible.builtin.command` to run `dkms autoinstall`. This is not idempotent by nature, but its effect (registering the kernel post-install hook) is idempotent in outcome — running it again on a module that already has a hook registered is a no-op in effect. Use `changed_when: false` to suppress false `changed` reporting on re-runs. Apply `when: ansible_virtualization_type != 'docker'`.

### Sub-step 3 — Implement `awg` userspace tool installation in `roles/amneziawg/tasks/userspace.yml`

Single-responsibility: this file owns only the `awg` binary — no DKMS logic, no config, no service management.

**Task: Download `awg` binary**

Use `ansible.builtin.get_url` to fetch the pre-built `awg` binary for Linux/amd64 from the AmneziaWG GitHub releases (e.g. `https://github.com/amnezia-vpn/amneziawg-tools/releases/download/{{ awg_tools_version }}/awg-linux-amd64`) to `/usr/bin/awg`. Set `mode: '0755'` and `owner: root` inline. The `get_url` module is idempotent by checksum when `checksum:` is provided — set `checksum: sha256:{{ awg_tools_sha256 }}` using a version-pinned variable in `roles/amneziawg/vars/main.yml`. If the binary already exists and the checksum matches, the task reports `ok`.

Pin `awg_tools_version` and `awg_tools_sha256` in `roles/amneziawg/vars/main.yml` alongside `awg_version`. These are role-internal constants, not operator-tunable variables, so they belong in `vars/main.yml` inside the role rather than `ansible/vars/main.yml`.

**Single-responsibility flag:** Do not install `wireguard-tools` (`wg` binary) here. `awg` is a drop-in that replaces `wg` for AmneziaWG interfaces. If `wireguard-tools` is needed for other purposes, that belongs in the `prerequisites` role. Flag this in the role README.

### Sub-step 4 — Implement config templating and service management in `roles/amneziawg/tasks/main.yml`

`tasks/main.yml` is the entry point. It must use `include_tasks:` to delegate DKMS work and userspace work to the sub-files authored in Sub-steps 2 and 3. The main file itself owns only the config file and service lifecycle — the two concerns that depend on operator-supplied variables.

**`include_tasks: dkms.yml`** — first, unconditionally.

**`include_tasks: userspace.yml`** — second, unconditionally.

**Task: Create `/etc/amneziawg/` directory**

Use `ansible.builtin.file` with `path: /etc/amneziawg`, `state: directory`, `mode: '0700'`, `owner: root`. Idempotent by nature (Ansible `file` module).

**Task: Template `awg0.conf`**

Use `ansible.builtin.template` with:

- `src: awg0.conf.j2`
- `dest: /etc/amneziawg/awg0.conf`
- `mode: '0600'`
- `owner: root`
- `notify: Restart awg-quick@awg0`

The template `roles/amneziawg/templates/awg0.conf.j2` must render using `awg_port`, `awg_jc`, `awg_jmin`, `awg_jmax`, `awg_private_key`, `awg_preshared_key`, `awg_client_public_key`, `awg_client_allowed_ips`, and `awg_address` from `ansible/vars/main.yml`. No variable defaulting inside the template — if a variable is missing, the template must fail loudly rather than silently render an empty field.

Relevant template shape (not source code — document expected section structure):

- `[Interface]` block: `Address`, `ListenPort`, `PrivateKey`, `Jc`, `Jmin`, `Jmax`
- `[Peer]` block: `PublicKey`, `PresharedKey`, `AllowedIPs`

**Task: Enable and start `awg-quick@awg0`**

Use `ansible.builtin.systemd` with:

- `name: awg-quick@awg0`
- `enabled: true`
- `state: started`
- `daemon_reload: true`

Apply `when: ansible_virtualization_type != 'docker'` because `awg-quick` depends on the kernel module and will fail to start in Docker. Document the guard inline.

**Handler: Restart `awg-quick@awg0`**

Create `roles/amneziawg/handlers/main.yml` with a single handler:

```yaml
- name: Restart awg-quick@awg0
  ansible.builtin.systemd:
    name: awg-quick@awg0
    state: restarted
  when: ansible_virtualization_type != 'docker'
```

The handler name must match the string passed to `notify:` in the template task exactly. This is the only handler in this role — no flush, no delegation to other roles. The `when:` guard prevents Docker failures without suppressing real-VPS restarts (AC-4).

### Sub-step 5 — Author `molecule/default/README.md` and complete the scenario

The README must include:

- **ACs exercised:** AC-3 (idempotency), AC-4 (variable-rotation idempotency via molecule's second converge with `awg_jc` changed), AC-5 (config contents verified against variables), AC-11 (Molecule scenario passes).
- **ACs not exercised in Docker (with explanation):**
  - AC-1: `lsmod | grep amneziawg` cannot be asserted — Docker shares the host kernel; DKMS cannot build or install a module. Manual checklist: SSH to real VPS, run `lsmod | grep amneziawg` after first deploy.
  - AC-8: Kernel module persistence across reboot cannot be simulated. Manual checklist: reboot VPS, wait ≤60 s for SSH, run `lsmod | grep amneziawg` — must succeed without re-running `make deploy`.
  - AC-2: DKMS build time cannot be profiled in Docker. Manual checklist: time the `dkms build` step on a clean VPS; if >5 min, open follow-up task to evaluate pre-built packages.
- **Variable-rotation test procedure:** The Molecule scenario `converge.yml` is run twice — once with `awg_jc: 5` and once with `awg_jc: 7`. The second run must report `changed=1` (the template task) and trigger the handler exactly once. Xray and Hysteria2 task lists must not appear in the diff because they are not part of this scenario.
- **How to run:** `cd ansible && molecule test -s default` for the full test including idempotency check.
- **DKMS build time note:** Profile the `dkms build` step on real hardware. If it consistently exceeds 5 minutes, open a follow-up task to evaluate pre-built DKMS packages or a kernel module cache, per the constraint in FEAT-0001 (AC-2, ≤15 min total).

### Sub-step 6 — Wire role into `playbook.yml` and verify ordering

Confirm that `ansible/playbook.yml` lists `amneziawg` as the second role (after `prerequisites`, before `xray`). This ordering was established in TASK-0001. If the file is still a stub, add the `amneziawg` entry in the correct position. No other changes to `playbook.yml` are in scope for this task.

Run `molecule test` (both platforms) to confirm:

1. First converge passes `verify.yml` assertions for config file, file mode, binary presence, and service-enabled state.
2. Molecule's built-in idempotency check (second converge) reports `changed=0` — AC-3 satisfied.
3. Third converge with `awg_jc` changed to a different value reports `changed=1` (template task only) and the handler fires exactly once — AC-4 satisfied.
4. `lsmod` assertion is absent from verify, confirming the Docker gap is correctly excluded.

## Edge Cases

The following edge cases are derived directly from the feature's acceptance criteria and the notes above:

1. **DKMS `add` exits non-zero when module already registered (AC-3):** `dkms add` returns exit code 3 if the module/version combination is already registered. The `creates: /var/lib/dkms/amneziawg/{{ awg_version }}` guard prevents re-running the command when the directory exists, so the exit code is never encountered on re-runs. However, if the directory exists but is corrupted (e.g., partial prior run), the guard will silently skip the registration. Mitigation: in the README, document that a corrupted DKMS state requires `dkms remove -m amneziawg -v {{ awg_version }} --all` followed by re-running `make deploy`.

2. **DKMS build fails silently if `linux-headers-{{ ansible_kernel }}` is absent (AC-2 / AC-8):** If the `prerequisites` role ran but kernel headers were not installed (e.g., Docker environment without the guard, or a VPS where headers were removed), `dkms build` will fail with a cryptic compiler error rather than a clear Ansible error. Mitigation: add a `ansible.builtin.stat` pre-check on `/usr/src/linux-headers-{{ ansible_kernel }}` before the `dkms build` task, and `fail` with a human-readable message if the directory is absent: `"Kernel headers for {{ ansible_kernel }} not found. Ensure the prerequisites role ran successfully."`.

3. **`awg0.conf` mode 0600 required to prevent `awg-quick` startup failure (AC-1 / AC-8):** `awg-quick` refuses to start if the config file is world-readable (exits non-zero with a permission error). The `ansible.builtin.template` task must set `mode: '0600'` explicitly. Do not rely on `umask` or Ansible defaults — they vary by environment. The Molecule verify step asserts `stat.mode == '0600'` to catch any regression here.

4. **`awg_jmin` > `awg_jmax` misconfiguration (AC-5):** AmneziaWG will reject a config where `Jmin > Jmax` at runtime, but the template will render it without error. Add an `ansible.builtin.assert` task in `tasks/main.yml` before the template task:

   ```yaml
   - name: Validate AmneziaWG jitter parameters
     ansible.builtin.assert:
       that:
         - awg_jmin | int <= awg_jmax | int
       fail_msg: "awg_jmin ({{ awg_jmin }}) must be <= awg_jmax ({{ awg_jmax }})"
   ```

   This fires at Ansible task evaluation time, before any file is written, so a bad variable change is caught before `awg-quick` is bounced (AC-4 safety net).

5. **Handler fires in Docker despite `when: ansible_virtualization_type != 'docker'` guard (AC-4):** Ansible evaluates handler `when:` conditions only at handler execution time. If the notify fires (because the template changed) but the handler's `when:` skips the restart, Ansible will report the handler as skipped, not failed. This is the desired behaviour in Docker — confirm in the Molecule verify step that the config file changed but no systemd error appears in the converge output. On a real VPS, the `when:` is false and the handler executes normally.

6. **Kernel upgrade after deploy breaks `lsmod | grep amneziawg` until `dkms autoinstall` runs (AC-8):** The `dkms autoinstall` command registers a kernel post-install hook so DKMS rebuilds the module for the new kernel automatically. If the hook is not registered (e.g., because the `dkms autoinstall` task was skipped on a prior run due to a Docker guard mismatch), a kernel upgrade will silently break AmneziaWG. Mitigation: the `dkms autoinstall` task must run on every play execution on a real VPS (`changed_when: false`), not just on first install. Add an explicit comment in `tasks/dkms.yml` explaining why `changed_when: false` is correct here and does not hide real failures.

7. **Port conflict between `awg_port` and other services (AC-6 / AC-3):** If `awg_port` is set to the same value as `xray_port` or `hysteria2_port`, `awg-quick` will fail to bind at start time. This role does not validate cross-role port uniqueness — that is the firewall role's responsibility (TASK-0006). Document in the role README that port uniqueness is enforced at the firewall layer, not here, and that duplicate ports will surface as a service start failure rather than an Ansible task failure.

8. **`awg-quick@awg0` restart scope does not bleed into other roles (AC-4):** The handler `Restart awg-quick@awg0` is defined in `roles/amneziawg/handlers/main.yml` and is scoped to the `amneziawg` role play. Ansible flushes role handlers at the end of the role unless `meta: flush_handlers` is called. Confirm that `playbook.yml` does NOT call `meta: flush_handlers` between roles — doing so would execute this role's handler during the next role's task list, which could cause an unexpected restart window while Xray or Hysteria2 tasks are mid-execution.
