#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# The forced command for dejima-guard's key is what stands between a key taken
# off the guard and a shell on the devbox. The guard is the machine holding the
# evidence about this one, so it is worth assuming somebody will eventually
# want it.
#
# Two failures matter and they fail in opposite directions:
#
#   - refusing something the guard needs, which breaks collection quietly. The
#     original one-liner did exactly this: `${SSH_ORIGINAL_COMMAND##* }` takes
#     the last word, so `drift --state` became `--state`, drift failed every
#     cycle, `reach` kept working, and the box looked watched while half of it
#     was not;
#   - permitting something it does not need, in particular `drift --accept`,
#     which rewrites the baseline. A key that can do that can tell the devbox
#     that whatever is on it now is normal.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SHELL_BIN="$REPO/bin/dejima-guard-shell"
    STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
    # sudo that runs what it was given, so what is under test is the whitelist
    # rather than whether this machine has sudo.
    printf '#!/bin/sh\nshift 2>/dev/null; exec "$@"\n' > "$STUB/sudo"
    printf '#!/bin/sh\necho "audit: $*"\n' > "$STUB/audit"
    chmod +x "$STUB/sudo" "$STUB/audit"
}

run_shell() { SSH_ORIGINAL_COMMAND="$1" AUDIT="$STUB/audit" PATH="$STUB:$PATH" run "$SHELL_BIN"; }

# --- what the guard needs ---------------------------------------------------

@test "reach is permitted and reaches the audit intact" {
    run_shell "dejima-devbox-audit reach"
    [ "$status" -eq 0 ]
    [ "$output" = "audit: reach" ]
}

@test "drift --state is permitted with both words" {
    # The one the obvious one-liner got wrong.
    run_shell "dejima-devbox-audit drift --state"
    [ "$status" -eq 0 ]
    [ "$output" = "audit: drift --state" ]
}

# --- what it must not permit ------------------------------------------------

@test "drift --accept is refused, because it would rewrite the baseline" {
    # The sharpest one. A key that can re-baseline can tell the devbox that
    # whatever an intruder left there is normal, and the guard would agree
    # from then on.
    run_shell "dejima-devbox-audit drift --accept"
    [ "$status" -ne 0 ]
    [[ "$output" == *refused* ]]
}

@test "an arbitrary command is refused" {
    run_shell "cat /etc/shadow"
    [ "$status" -ne 0 ]
    [[ "$output" == *refused* ]]
}

@test "a permitted command with something appended is refused whole" {
    # Matched exactly, not by prefix. A prefix match would let anything ride
    # in behind a command that is allowed.
    run_shell "dejima-devbox-audit reach; cat /etc/shadow"
    [ "$status" -ne 0 ]
    [[ "$output" != *"audit: reach"* ]]
}

@test "an empty command is refused rather than falling through to a shell" {
    # An interactive ssh with no command sets nothing. Falling through here
    # would turn the forced command into no restriction at all.
    run_shell ""
    [ "$status" -ne 0 ]
    [[ "$output" == *refused* ]]
}

@test "radius is refused, though it is read-only" {
    # It inventories credentials. The guard has no use for it, and a whitelist
    # is what the guard needs rather than what happens to be harmless.
    run_shell "dejima-devbox-audit radius"
    [ "$status" -ne 0 ]
}

@test "the refusal names what was refused" {
    # A guard whose command was rejected otherwise gets an empty answer, and an
    # empty answer is the one thing this design refuses to read as nothing to
    # report - so the operator needs the reason in the log, not silence.
    run_shell "dejima-devbox-audit radius"
    [[ "$output" == *"dejima-devbox-audit radius"* ]]
}

# --- what the runbook promises ----------------------------------------------

@test "bootstrap installs it, so the runbook step is one line in a file" {
    grep -q 'bin/dejima-guard-shell' "$REPO/bin/dejima-devbox-bootstrap"
}

@test "the runbook never reads the guard's key from a file on the devbox" {
    # The key is generated on the guard and never leaves it, so there is no
    # guard_key.pub on this box to cat. The section used to open with a block
    # that did exactly that, and it failed on the first line for everyone who
    # followed it.
    ! grep -q 'cat guard_key.pub' "$REPO/docs/building-a-devbox.md"
}

@test "every ssh example offering a key also restricts ssh to it" {
    # `-i` ADDS a key to the ones offered. With the operator's own key present,
    # or an agent holding one, ssh authenticates with that instead, no forced
    # command applies, and a check of the restriction reports it missing when
    # it is fine. Four examples in the runbook were wrong this way.
    while IFS= read -r line; do
        [[ "$line" == *IdentitiesOnly=yes* ]] \
            || { echo "ssh -i without IdentitiesOnly: $line" >&2; false; }
    done < <(grep -rh 'ssh .*-i ' "$REPO/docs" "$REPO/upgrades" || true)
}

@test "the runbook section has an anchor that survives being renumbered" {
    # Its headings are numbered, so a section inserted above this one renames
    # it and orphans every link in - including the one in the v5 note and the
    # one in dejima-guard, which is a different repository and will not be
    # renumbered along with it.
    grep -q '<a id="guard-access">' "$REPO/docs/building-a-devbox.md"
    ! grep -rq 'building-a-devbox.md#7-' "$REPO/docs" "$REPO/upgrades" "$REPO/proxmox"
}

@test "the sudoers line in the runbook names both permitted invocations" {
    # If it named the program alone it would also permit drift --accept, and
    # the forced command would be the only thing standing in the way.
    line=$(grep 'NOPASSWD' "$REPO/docs/building-a-devbox.md")
    [[ "$line" == *"dejima-devbox-audit reach"* ]]
    [[ "$line" == *"dejima-devbox-audit drift --state"* ]]
    [[ "$line" != *"NOPASSWD: /usr/local/sbin/dejima-devbox-audit,"* ]]
}
