---
id: TASK-0012
status: todo
feature_id: FEAT-0005
---

## Description

A `make rotate` Makefile target mutates `vars/main.yml` with a new port and SNI, re-runs the Ansible playbook idempotently, runs `make check`, and prints the new connection parameters to stdout. After this task, an operator under censorship pressure can restore connectivity to a rotated config within five minutes by running a single command.

Done looks like:

- `Makefile` target `rotate` executes the following stages in sequence:
  1. If `ROTATE_SECRETS=1` is set, run `make secrets` (FEAT-0002) to regenerate the Xray UUID and x25519 keypair.
  2. Invoke `scripts/new-port.sh` to obtain a new port; capture the old `xray_port` value from `vars/main.yml` before overwriting it.
  3. If `SNI=<value>` is provided as a make variable, use that value directly; otherwise invoke `scripts/pick-sni.sh` to select from `config/sni-candidates.txt`. Fail loudly if neither produces a value.
  4. Overwrite `xray_port` and `xray_server_name` in `vars/main.yml` with the new values using `sed` or equivalent in-place substitution (no Python, no extra tooling beyond POSIX utilities).
  5. Run `ansible-playbook -i ansible/inventory/ ansible/playbook.yml` and capture stdout/stderr.
  6. Assert that neither `Restart amneziawg` nor `Restart hysteria2` appears in the Ansible output; if either does, print a warning to stderr but do not fail the target.
  7. Run `make check` (FEAT-0003).
- On success: print to stdout `New port: <port>` and `New SNI: <sni>` so the operator can update client configs.
- On `make check` failure: exit non-zero; print to stderr `Old port: <old_port>` and `New port: <new_port>` for diagnosis. Do not revert `vars/main.yml`.
- A shell test (runnable in CI without a real VPS) verifies exit-code behaviour by mocking `scripts/new-port.sh`, `scripts/pick-sni.sh`, `ansible-playbook`, and `make check` with stub scripts.
- `SNI=example.com make rotate` sets `xray_server_name: "example.com"` without reading `config/sni-candidates.txt`; the file need not be present (AC-7).

## Notes

- Depends on TASK-0009 (vars schema stable with `xray_reality_dest`), TASK-0010 (`scripts/new-port.sh`), TASK-0011 (`scripts/pick-sni.sh`), TASK-0007 (Makefile exists with `deploy` target and `check` stub).
- `make rotate` must not restart AmneziaWG or Hysteria2. This property is structurally guaranteed by Ansible idempotency (only Xray and firewall role vars change), but the output assertion in stage 6 provides an explicit fast-fail if idempotency is violated by a future role change.
- The `sed` in-place substitution for `vars/main.yml` must handle both quoted and unquoted YAML values (`xray_port: 12345` and `xray_port: "12345"`). Test with both forms.
- Document clearly in a `## After rotation` comment block in the Makefile (or in `ansible/README.md`) that the operator must `git add ansible/vars/main.yml && git commit` after a successful rotation to keep the repo in sync, and that `git stash` or `git checkout` would silently revert to the pre-rotation config.
- `ROTATE_SECRETS=1 make rotate` is additive: it runs `make secrets` first and then proceeds with port+SNI rotation. The two are not mutually exclusive.
- Do not add retry logic inside `make rotate` itself; if `make check` fails, the operator re-runs `make rotate` or manually restores the previous port. Auto-revert is explicitly out of scope.
