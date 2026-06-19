#!/bin/sh
# POSIX sh — no bashisms (TASK-0007 sub-step 1, AC-10).
# Verifies `make deploy`'s three-stage exit-code coupling (SOPS decrypt,
# ansible-playbook, connectivity check) and that the decrypted secrets file
# never survives a failed run.
#
# Usage: sh tests/test_deploy_exit_codes.sh [path-to-repo-root]

root="${1:-.}"
secrets_file="$root/ansible/vars/secrets.yml"
fail_count=0

cleanup() {
    rm -f "$secrets_file"
}

# check DESCRIPTION zero|nonzero EXPECTED_SUBSTRING ENV_ASSIGNMENTS...
# Runs `make deploy` in $root with the given stage stubs, asserts the exit
# code class and (if non-empty) that EXPECTED_SUBSTRING appears in output.
check() {
    description="$1"
    expect="$2"
    expect_grep="$3"
    shift 3

    cleanup
    output=$(cd "$root" && env "$@" make deploy 2>&1)
    code=$?
    cleanup

    ok=1
    if [ "$expect" = "zero" ] && [ "$code" -ne 0 ]; then
        ok=0
    fi
    if [ "$expect" = "nonzero" ] && [ "$code" -eq 0 ]; then
        ok=0
    fi
    if [ -n "$expect_grep" ] && ! printf '%s' "$output" | grep -qF "$expect_grep"; then
        ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        echo "PASS: $description"
    else
        echo "FAIL: $description (exit=$code)"
        printf '%s\n' "$output"
        fail_count=$((fail_count + 1))
    fi
}

check_file_absent() {
    description="$1"
    if [ -e "$secrets_file" ]; then
        echo "FAIL: $description (secrets file still present: $secrets_file)"
        fail_count=$((fail_count + 1))
    else
        echo "PASS: $description"
    fi
}

# Case 1 — SOPS stage fails
check "SOPS failure -> non-zero exit + correct message" nonzero \
    "ERROR: SOPS decrypt failed" \
    SOPS_CMD=false ANSIBLE_CMD=true CONNECTIVITY_CHECK=true
check_file_absent "secrets file absent after failed SOPS stage"

# Case 2 — ansible-playbook stage fails
check "ansible-playbook failure -> non-zero exit + correct message" nonzero \
    "ERROR: ansible-playbook failed" \
    SOPS_CMD=true ANSIBLE_CMD=false CONNECTIVITY_CHECK=true
check_file_absent "secrets file absent after failed ansible stage"

# Case 3 — connectivity check stage fails
check "connectivity check failure -> non-zero exit + correct message" nonzero \
    "ERROR: Connectivity check failed" \
    SOPS_CMD=true ANSIBLE_CMD=true CONNECTIVITY_CHECK=false

# Case 4 — all stages succeed
check "all stages succeed -> exit 0" zero "" \
    SOPS_CMD=true ANSIBLE_CMD=true CONNECTIVITY_CHECK=true

# Case 5 — default ANSIBLE_CMD must consume the decrypted secrets file;
# otherwise stage 1's output never reaches stage 2 (see ANSIBLE_CMD's
# default value, deliberately left unset here to check that default).
dryrun=$(cd "$root" && env SOPS_CMD=true CONNECTIVITY_CHECK=true make -n deploy 2>&1)
if printf '%s' "$dryrun" | grep -qF -- '-e @ansible/vars/secrets.yml'; then
    echo "PASS: default ANSIBLE_CMD wires the decrypted secrets file"
else
    echo "FAIL: default ANSIBLE_CMD wires the decrypted secrets file"
    printf '%s\n' "$dryrun"
    fail_count=$((fail_count + 1))
fi

if [ "$fail_count" -eq 0 ]; then
    echo "All test_deploy_exit_codes cases passed."
    exit 0
else
    echo "$fail_count case(s) failed."
    exit 1
fi
