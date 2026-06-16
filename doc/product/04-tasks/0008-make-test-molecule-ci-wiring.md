---
id: TASK-0008
status: todo
feature_id: FEAT-0001
---

## Description

A `make test` Makefile target runs all Molecule scenarios across all roles in sequence and exits 0 only when every scenario passes. After this task, CI can gate any PR touching an Ansible role by running `make test`, satisfying AC-11.

Done looks like:

- `Makefile` target `test` discovers and runs the Molecule scenario for each role (`prerequisites`, `amneziawg`, `xray`, `hysteria2`, `firewall`) using `molecule test` in each role's directory.
- The output for each scenario is prefixed with the role name and lists the ACs it exercises, matching the documentation requirement in AC-11.
- `make test` exits 0 only when all scenarios pass; the first failure halts execution and identifies which role's scenario failed.
- A CI configuration file (e.g., `.github/workflows/test.yml`) runs `make test` on pull requests targeting any file under `ansible/roles/`. The workflow requires only `ansible`, `molecule[docker]`, and Docker to be available — no real VPS, no age key.
- Running `make test` locally on a workstation with Docker and the required Python packages succeeds within a reasonable time (documented in `ansible/README.md`).

## Notes

- Depends on TASK-0002 through TASK-0006 (each role must have a passing Molecule scenario before this wiring task is meaningful).
- Depends on TASK-0007 (Makefile exists so `test` target can be added alongside `deploy`).
- The `amneziawg` Molecule scenario skips kernel-module assertions in Docker (documented in TASK-0003); `make test` must still exit 0 when those assertions are correctly marked as skipped, not failed.
- Pin the `molecule` and `molecule-plugins[docker]` versions in a `requirements-dev.txt` (or `pyproject.toml` dev dependency) to ensure reproducible CI runs. Document the pinned versions in `ansible/README.md`.
- Real-VPS tests (AC-1 AmneziaWG portion, AC-2, AC-7, AC-8) are explicitly not part of `make test`. The CI workflow README must state this gap and link to the manual real-VPS test checklist.

## Implementation Plan

This task has a single concern: wire the already-complete per-role Molecule scenarios into one `make test` command that CI can invoke, and add the GitHub Actions workflow that triggers it. No new Molecule scenarios are authored here — that belongs to TASK-0002 through TASK-0006.

### Sub-step 1 — Write a failing shell test for the `test-molecule` Make target (TDD)

Create `tests/test_make_test.sh` before touching the Makefile or CI file. This script is the test harness for the wiring contract itself; it must run under POSIX sh.

Test cases to implement in `tests/test_make_test.sh`:

1. **All scenarios pass → exit 0.** Stub `molecule test` as `true` for each role directory and assert that `make test-molecule` exits 0.
2. **First failing role halts execution and exits non-zero.** Stub `molecule test` for the `prerequisites` role as `false`; assert `make test-molecule` exits non-zero and that the error output names `prerequisites` as the failing role. Remaining roles must not be attempted (verify by asserting their stub is never called — e.g., use a counter file or absence of a sentinel).
3. **Middle failing role (`xray`) halts and names the role.** Stubs for `prerequisites`, `amneziawg` are `true`; `xray` is `false`. Assert exit non-zero and that `xray` appears in the error output.
4. **Skipped Molecule assertions (amneziawg kernel skip) do not cause non-zero exit.** Stub `molecule test` for all roles as `true` (Molecule itself handles `skipped` vs `failed`; the test confirms the shell wrapper does not conflate them). Assert exit 0.

Single-responsibility note: this file tests only the `test-molecule` target's orchestration contract. The `deploy` exit-code contract is already covered by `tests/test_deploy_exit_codes.sh` (TASK-0007 scope); do not merge them.

### Sub-step 2 — Add `test-molecule` and `test` targets to the `Makefile`

File to modify: `Makefile` (root of repository, created in TASK-0007).

**Overridable variable to declare** (alongside the existing TASK-0007 variables):

```
ROLES ?= prerequisites amneziawg xray hysteria2 firewall
ANSIBLE_ROLES_DIR ?= ansible/roles
```

**`test-molecule` target** — iterate over `$(ROLES)` in order using a `for` loop in the recipe shell. For each role:

1. Print a header line: `=== [<role>] molecule test — covers: <AC list> ===` using a lookup table (a Make variable or embedded shell `case` statement mapping role name → AC list). The AC mapping is:
   - `prerequisites` → `AC-3, AC-9`
   - `amneziawg` → `AC-1 (partial — kernel module skipped in Docker), AC-3`
   - `xray` → `AC-3, AC-4, AC-5`
   - `hysteria2` → `AC-3, AC-4, AC-5`
   - `firewall` → `AC-3, AC-6`
2. `cd $(ANSIBLE_ROLES_DIR)/<role> && molecule test`. On non-zero exit, print `ERROR: molecule test failed for role <role>` to stderr and `exit 1` — halting the loop immediately (use `|| exit 1` or an explicit `if` block; do not use `set -e` alone, which is unreliable across Make recipe shells).

POSIX compliance: the recipe must not use `[[ ]]`, `local`, or `$PIPESTATUS`. Use `$?` with explicit `if [ $? -ne 0 ]` checks.

**`test` target** — update the existing stub `test` target (added in TASK-0007 as `test-deploy`-only) to depend on both `test-deploy` and `test-molecule`:

```
test: test-deploy test-molecule
```

Update `.PHONY` to include `test-molecule`.

Single-responsibility check: `test-molecule` only loops over roles and calls `molecule test`. It does not also invoke `test-deploy` or set up Python. If the loop body grows to include Python env setup, that must be extracted into a separate `_setup-molecule-env` prerequisite target, not inlined.

### Sub-step 3 — Create `requirements-dev.txt` with pinned Molecule versions

Create `requirements-dev.txt` at the repository root (not inside `ansible/`).

Contents — pin exact versions discovered to be compatible with the role scenarios authored in TASK-0002 through TASK-0006:

```
molecule==<exact-version>
molecule-plugins[docker]==<exact-version>
ansible==<exact-version>
```

Rationale for pinning to exact versions (not `~=` or `>=`): reproducible CI runs are an explicit requirement in the Notes. Minor Molecule releases have historically changed scenario step behaviour (e.g., `idempotency` step enablement defaults changed between Molecule 6.0 and 6.1). Use `==` not `~=`.

Do **not** include `boto3`, `google-cloud`, or other cloud-provider packages — YAGNI; Docker driver is the only driver in use.

### Sub-step 4 — Create `.github/workflows/test.yml` CI workflow

Create `.github/workflows/test.yml` (do not modify any existing workflow file; TASK-0007 created `.github/workflows/ci.yml` for the deploy exit-code test — keep concerns separate).

Workflow contract:

- **Trigger:** `pull_request` with `paths` filter `['ansible/roles/**']`. This ensures the workflow fires on any PR touching a role file but not on unrelated changes (e.g., docs-only PRs).
- **Job name:** `molecule-tests`
- **Runner:** `ubuntu-latest`
- **Steps:**
  1. `actions/checkout@v4` — check out the repository.
  2. `actions/setup-python@v5` with `python-version: '3.11'` — consistent Python version across CI runs.
  3. `pip install -r requirements-dev.txt` — install pinned Molecule and Ansible.
  4. Ensure Docker is available (it is pre-installed on `ubuntu-latest` GitHub-hosted runners; add a `docker info` sanity step to fail fast if not).
  5. `make test-molecule` — run all scenarios.

The workflow must not require any secrets (`AGE_SECRET_KEY`, VPS SSH key, etc.). Add a comment at the top of the file: `# No secrets required — Docker driver only. Real-VPS tests (AC-1 partial, AC-2, AC-7, AC-8) are run manually; see ansible/README.md#real-vps-test-checklist.`

Do not add a `deploy` job to this workflow file — separation of concerns between test CI and deploy CI.

### Sub-step 5 — Update `ansible/README.md` with developer setup and coverage gap documentation

File to modify: `ansible/README.md`.

Add or extend the following sections:

**`## Running Tests Locally`** — document the exact commands a developer runs on a fresh workstation:

```sh
pip install -r requirements-dev.txt   # install pinned molecule + ansible
make test                             # runs test-deploy then test-molecule
```

State the pinned versions explicitly (copy from `requirements-dev.txt`) so a developer reading the README without running the install command knows what versions are expected.

State the Docker requirement: Docker daemon must be running and the current user must be able to run `docker run` without `sudo`. Note that `ghcr.io/geerlingguy/docker-*-ansible` images require a privileged container; list the `--cap-add SYS_ADMIN` requirement and confirm that `molecule.yml` in each scenario handles this without manual user intervention.

**`## Real-VPS Test Checklist`** — add a named anchor `#real-vps-test-checklist` for the CI workflow comment to link to. List the ACs not covered by `make test`:

- AC-1 (AmneziaWG `lsmod` assertion) — requires real kernel
- AC-2 (cold deploy timing ≤ 15 min) — Docker I/O does not reflect real VPS
- AC-7 (client-IP whitelist at network level) — requires real NIC
- AC-8 (AmneziaWG survives reboot) — requires real kernel and reboot

State explicitly: "These ACs must be verified manually before any PR touching `ansible/roles/amneziawg/` or `ansible/roles/firewall/` is merged."

## Edge Cases

The following edge cases are derived directly from the feature's acceptance criteria and the Notes:

1. **`amneziawg` skipped assertions must not poison `make test` exit code (AC-11, Notes).** Molecule reports skipped tasks as `skipped`, not `failed`. The `molecule test` command exits 0 when all assertions pass or skip; it exits non-zero only on `failed`. The `test-molecule` loop must propagate the `molecule test` exit code verbatim — do not post-process Molecule output to detect "skipped" lines and convert them to failures. Regression vector: if a future scenario mistakenly marks a skip as `failed` (e.g., by using `fail_when: result.skipped`), `make test` will correctly surface it.

2. **Role directory missing or `molecule/default/` absent halts the loop (AC-11).** If one of the five role directories listed in `$(ROLES)` does not exist or has no `molecule/default/molecule.yml`, `molecule test` exits non-zero. The loop must not silently continue; the error message must name the role. This prevents a scenario where a role is renamed and the stale name in `$(ROLES)` silently runs zero tests and exits 0.

3. **`make test` partial failure must not silently pass (AC-11).** Using `for role in $(ROLES); do molecule test || exit 1; done` inside a single Make recipe shell invocation correctly propagates the first failure. Do not use `$(foreach ...)` with separate recipe lines, which causes Make to invoke a new shell for each iteration and may swallow exit codes depending on `.ONESHELL` configuration.

4. **`requirements-dev.txt` version drift between local and CI environments.** If a developer installs `molecule` without `requirements-dev.txt` (e.g., `pip install molecule`), a different version may be used locally, causing CI-only failures. The `ansible/README.md` instructions must explicitly say "always install from `requirements-dev.txt`", and the CI step must use `pip install -r requirements-dev.txt` (not `pip install molecule`).

5. **GitHub Actions `paths` filter and force-push edge case (AC-11).** The `pull_request` trigger with `paths: ['ansible/roles/**']` does not fire when only non-role files change (correct). However, if a PR's base branch is force-pushed and the diff recalculation excludes role files, the workflow may not trigger. This is acceptable per scope — the AC only requires that PRs _touching_ a role file are gated. Document this limitation in the workflow file as a comment.

6. **`make test` invoked without Docker running.** `molecule test` exits non-zero when the Docker daemon is unreachable. The `test-molecule` loop will catch this via the `|| exit 1` guard and print `ERROR: molecule test failed for role prerequisites` (whichever role runs first). The error message will include Molecule's own "Cannot connect to the Docker daemon" output above it. No additional wrapping is needed — the existing contract surfaces the failure clearly enough.
