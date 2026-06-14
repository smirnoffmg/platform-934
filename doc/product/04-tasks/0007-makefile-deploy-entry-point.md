---
id: TASK-0007
status: todo
feature_id: FEAT-0001
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
