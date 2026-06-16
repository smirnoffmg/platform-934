---
id: TASK-0007
status: done
feature_id: FEAT-0001
completed_at: "2026-06-16T14:17:02.960Z"
commit_sha: 75c99a568034ca25b722f82210d29e5ad97b6027
---

## Description

A `Makefile` at the repository root provides a `make deploy` target that orchestrates three stages in sequence — SOPS decrypt, `ansible-playbook`, connectivity check — and exits non-zero with a human-readable error message identifying the failed stage. After this task, `make deploy` is the single command an operator runs to provision or update a VPS, satisfying AC-9 and AC-10.

Done looks like:

- `Makefile` target `deploy` executes stages in strict order:
  1. SOPS decrypt: invokes `sops --decrypt ansible/vars/secrets.enc.yml > ansible/vars/secrets.yml` (or equivalent). On failure, prints `ERROR: SOPS decrypt failed — check AGE_SECRET_KEY or ~/.config/sops/age/keys.txt` and exits non-zero.
  2. `ansible-playbook`: invokes `ansible-playbook -i ansible/inventory/ ansible/playbook.yml`. On failure, prints `ERROR: ansible-playbook failed — see output above` and exits non-zero.
  3. Connectivity check: invokes the check script defined in FEAT-0003 (referenced here as a stub command; wired in FEAT-0003). On failure, prints `ERROR: Connectivity check failed — proxy stack may not be reachable` and exits non-zero.
- `make deploy` exits 0 if and only if all three stages succeed.
- The decrypted secrets file is deleted (or not written to disk) after the playbook run — the Makefile must not leave plaintext secrets at rest on the operator's workstation. Use a `trap` or `.INTERMEDIATE` target to ensure cleanup even on failure.
- A Molecule/shell test or a `make test` sub-target verifies the exit-code coupling (AC-10): mocking stage 1, 2, or 3 to fail each produces a non-zero exit and the correct error message.

## Notes

- Depends on TASK-0001 (playbook.yml path and inventory structure) and on role tasks TASK-0002 through TASK-0006 being defined (so the playbook has real roles to run).
- The connectivity check command is a stub at this stage; FEAT-0003 defines the real command. Use a variable or Make macro (e.g., `CONNECTIVITY_CHECK ?= echo "connectivity check stub"`) so it can be overridden without editing the Makefile.
- SOPS integration is specified by FEAT-0002; this task wires the SOPS call into the Makefile. If FEAT-0002 is not yet complete, the SOPS stage may be a stub that copies a pre-existing plaintext file.
- The Makefile must not rely on shell features beyond POSIX sh; avoid bashisms to preserve AC-9 (fresh-workstation reproducibility).
- AC-9 requires that cloning the repo and running `make deploy` (with the age key provided) succeeds with no additional manual steps. Verify that all prerequisites (`ansible`, `sops`, `age`) are checked at the start of `make deploy` with actionable error messages if missing.

## Implementation Plan

### Sub-step 1 — Write failing shell tests for exit-code coupling (TDD, AC-10)

Create `tests/test_deploy_exit_codes.sh`. This script is the test harness; it must pass before the Makefile target is considered done.

Each test case calls `make deploy` with one stage overridden to a failing stub and asserts:

- Exit code is non-zero.
- stderr/stdout contains the exact error string for that stage.

Test cases to implement:

1. `SOPS_CMD="false"` → expect exit ≠ 0 and message `ERROR: SOPS decrypt failed`.
2. `ANSIBLE_CMD="false"` → expect exit ≠ 0 and message `ERROR: ansible-playbook failed`.
3. `CONNECTIVITY_CHECK="false"` → expect exit ≠ 0 and message `ERROR: Connectivity check failed`.
4. All three stubs succeed (`true`) → expect exit 0.
5. Secrets file `ansible/vars/secrets.yml` must not exist after a failed SOPS stage (cleanup verification).
6. Secrets file must not exist after a failed Ansible stage (cleanup verification across the boundary).

The harness must be runnable with `sh tests/test_deploy_exit_codes.sh` (POSIX sh, no bash required). Wire it into `make test` as a distinct target (`test-deploy`) once the Makefile exists.

Single-responsibility note: `tests/test_deploy_exit_codes.sh` tests only the `deploy` target's exit-code contract. Molecule scenario invocation belongs in `make test-molecule` (TASK-0008 scope); do not merge them here.

### Sub-step 2 — Implement `Makefile` with `deploy` target

File to create: `Makefile` at the repository root.

**Overridable variables (declare before all targets):**

```
SOPS_CMD        ?= sops --decrypt ansible/vars/secrets.enc.yml
ANSIBLE_CMD     ?= ansible-playbook -i ansible/inventory/ ansible/playbook.yml
CONNECTIVITY_CHECK ?= echo "connectivity check stub"
SECRETS_FILE    := ansible/vars/secrets.yml
```

**`_check-prereqs` internal target** (not `.PHONY`-exposed to operators):

Check that `ansible`, `sops`, and `age` are on `PATH` using `command -v`. On any missing binary, print `ERROR: <binary> not found — install it before running make deploy` and exit 1. This guards AC-9: a fresh workstation with a missing dependency fails loudly before any side effect.

**`deploy` target** structure using a single `$(shell ...)` recipe written in POSIX sh:

Use a `trap` inside the recipe shell invocation to ensure `$(SECRETS_FILE)` is removed on exit (both success and failure). The trap target is `rm -f $(SECRETS_FILE)`.

Stage sequencing within the recipe:

1. Run `$(SOPS_CMD) > $(SECRETS_FILE)`. On non-zero exit, print the SOPS error message and `exit 1` (the trap fires on exit, removing the partially-written file).
2. Run `$(ANSIBLE_CMD)`. On non-zero exit, print the Ansible error message and `exit 1` (trap fires, removing the secrets file).
3. Run `$(CONNECTIVITY_CHECK)`. On non-zero exit, print the connectivity error message and `exit 1`.
4. `exit 0` — trap fires and cleans up secrets file on success too.

Implementation note on POSIX compliance: the recipe must use `sh -c '...'` or rely on Make's default shell. Avoid `[[ ]]`, `local`, `source`, `$PIPESTATUS`, `$((...))` arithmetic — all are bashisms. Use `$?` checks after each command.

**`.PHONY` declaration:** list `deploy`, `test`, `test-deploy`, `_check-prereqs`.

**`test-deploy` target:** runs `sh tests/test_deploy_exit_codes.sh`. Depends on nothing outside the test file.

**`test` target:** depends on `test-deploy` at minimum; TASK-0008 will append `test-molecule`.

### Sub-step 3 — Wire `test-deploy` into CI and verify cleanup contract

In `.github/workflows/ci.yml` (create if absent, or extend if present), add a job step:

```
- name: Test deploy exit-code coupling
  run: make test-deploy
```

This job requires no real SOPS key, no real VPS — all stages are stubs.

Verify the cleanup contract explicitly in CI by checking that `ansible/vars/secrets.yml` is absent after the test run:

```
- name: Assert secrets file absent after test run
  run: test ! -f ansible/vars/secrets.yml
```

Single-responsibility note: CI job wiring for Molecule scenarios (`make test-molecule`) belongs to TASK-0008, not here. This step adds only the `test-deploy` job.

### Edge Cases (derived from AC-9, AC-10, and the cleanup requirement)

| Edge case                                                                                                 | Handling                                                                                                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGE_SECRET_KEY` unset and `~/.config/sops/age/keys.txt` absent                                           | SOPS stage fails; `_check-prereqs` does not catch this (it only checks the binary), but the SOPS stage error message includes both lookup locations so the operator knows what to provide. No additional Make logic needed.                          |
| `ansible/vars/secrets.enc.yml` missing                                                                    | SOPS stage exits non-zero; same error path as a decryption failure. The error message is correct without special-casing.                                                                                                                             |
| `ansible/vars/secrets.yml` already exists before `make deploy` (leftover from a previous interrupted run) | The `trap` in the recipe will overwrite it during the SOPS stage and clean it up on exit regardless. No stale-file guard needed because the trap always removes it.                                                                                  |
| Make is invoked with `-k` (keep-going flag)                                                               | `deploy` target uses `exit 1` inside the recipe shell; Make cannot override an explicit shell exit. The `-k` flag does not propagate past a recipe exit. No special handling needed.                                                                 |
| Operator runs `make deploy` in parallel (`-j`)                                                            | The `deploy` target has no sub-targets to parallelise; all three stages are sequential within one recipe. Parallel Make invocation has no effect.                                                                                                    |
| Disk full — SOPS output to `secrets.yml` is truncated                                                     | SOPS itself will exit non-zero when the write fails; the SOPS error path fires and cleans up.                                                                                                                                                        |
| CONNECTIVITY_CHECK is overridden to a multi-word command (e.g., `./scripts/check.sh --timeout 30`)        | The variable is expanded unquoted inside the recipe. Document that values with spaces must be wrapped: `CONNECTIVITY_CHECK='./scripts/check.sh --timeout 30'`.                                                                                       |
| `make test-deploy` run without Make available (pure CI shell)                                             | `tests/test_deploy_exit_codes.sh` is a standalone POSIX sh script; it can be invoked directly with `sh` if Make is unavailable. Ensure the script accepts an optional first argument as the path to the Makefile directory (`$1` defaulting to `.`). |
