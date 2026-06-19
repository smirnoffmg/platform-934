#!/bin/sh
# POSIX sh — no bashisms (TASK-0008 sub-step 1).
# Verifies `make test-molecule`'s orchestration contract: iterates $(ROLES)
# in order, halts on the first failing role and names it, and does not
# conflate Molecule's own skipped/failed distinction.
#
# Usage: sh tests/test_make_test.sh [path-to-repo-root]

root="${1:-.}"
fail_count=0

# A fake `molecule` on PATH stands in for the real binary so we can control
# per-role pass/fail without running real scenarios. It identifies "the
# role" by the basename of its cwd, since the Makefile does
# `cd $(ANSIBLE_ROLES_DIR)/<role> && molecule test`.
shim_dir=$(mktemp -d)
cat > "$shim_dir/molecule" <<'SHIM'
#!/bin/sh
echo "$(basename "$PWD")" >> "$FAKE_MOLECULE_LOG"
[ "$(basename "$PWD")" = "${FAKE_MOLECULE_FAIL_ROLE:-}" ] && exit 1
exit 0
SHIM
chmod +x "$shim_dir/molecule"

cleanup_shim() {
    rm -rf "$shim_dir"
}
trap cleanup_shim EXIT

# run_case DESCRIPTION FAIL_ROLE EXPECT(zero|nonzero) EXPECT_GREP EXPECT_INVOKED
run_case() {
    description="$1"
    fail_role="$2"
    expect="$3"
    expect_grep="$4"
    expect_invoked="$5"

    log=$(mktemp)
    output=$(cd "$root" && PATH="$shim_dir:$PATH" \
        FAKE_MOLECULE_LOG="$log" FAKE_MOLECULE_FAIL_ROLE="$fail_role" \
        make test-molecule 2>&1)
    code=$?
    invoked=$(tr '\n' ' ' < "$log" | sed 's/ *$//')
    rm -f "$log"

    ok=1
    if [ "$expect" = "zero" ] && [ "$code" -ne 0 ]; then ok=0; fi
    if [ "$expect" = "nonzero" ] && [ "$code" -eq 0 ]; then ok=0; fi
    if [ -n "$expect_grep" ] && ! printf '%s' "$output" | grep -qF "$expect_grep"; then ok=0; fi
    if [ "$invoked" != "$expect_invoked" ]; then ok=0; fi

    if [ "$ok" -eq 1 ]; then
        echo "PASS: $description"
    else
        echo "FAIL: $description (exit=$code, invoked=[$invoked], expected_invoked=[$expect_invoked])"
        printf '%s\n' "$output"
        fail_count=$((fail_count + 1))
    fi
}

# Case 1 — all roles pass
run_case "all roles pass -> exit 0, all roles invoked in order" \
    "" zero "" \
    "prerequisites amneziawg xray hysteria2 firewall"

# Case 2 — first role (prerequisites) fails: halts immediately, names it
run_case "first role failing halts immediately and names it" \
    "prerequisites" nonzero "prerequisites" \
    "prerequisites"

# Case 3 — middle role (xray) fails: earlier roles ran, later roles did not
run_case "middle role failing halts after it and names it" \
    "xray" nonzero "xray" \
    "prerequisites amneziawg xray"

# Case 4 — stub always succeeds (stand-in for Molecule's own skipped-vs-
# failed distinction): the shell wrapper must not conflate them and must
# propagate the molecule exit code verbatim.
run_case "stub success (skip-equivalent) does not poison exit code" \
    "" zero "" \
    "prerequisites amneziawg xray hysteria2 firewall"

if [ "$fail_count" -eq 0 ]; then
    echo "All test_make_test cases passed."
    exit 0
else
    echo "$fail_count case(s) failed."
    exit 1
fi
