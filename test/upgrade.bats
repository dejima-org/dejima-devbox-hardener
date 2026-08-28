#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# The two things this tool must not do, both of which are the same mistake the
# audit is built around not making:
#
#   - report "up to date" about versions it has never heard of;
#   - record an operator's claim about the hypervisor that the machine in front
#     of it already contradicts.
#
# Everything below is one of those two, or the arithmetic that decides which
# halves of an upgrade are outstanding.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TOOL="$REPO/bin/dejima-devbox-upgrade"
    STATE_DIR="$BATS_TEST_TMPDIR/etc"
    STUB_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STATE_DIR" "$STUB_DIR"
}

# Run the tool against a throwaway state dir, never the host's.
run_tool() { CONF_DIR="$STATE_DIR" PATH="$STUB_DIR:$PATH" run "$TOOL" "$@"; }

write_state() { printf '%s\n' "$@" > "$STATE_DIR/state"; }

# A stand-in for the verify-node command, exiting how the test wants.
stub_audit() {
    printf '#!/bin/sh\nexit %s\n' "$1" > "$STUB_DIR/dejima-devbox-audit"
    chmod +x "$STUB_DIR/dejima-devbox-audit"
}

# --- knowing where you are --------------------------------------------------

@test "a host with no state file is not assumed to be v1" {
    # An untracked host and a host whose state file was deleted are identical
    # from in here. Picking the friendlier reading is how a check comes to be
    # believed when it does not know.
    run_tool status --no-verify
    [ "$status" -ne 0 ]
    [[ "$output" == *"predates version tracking"* ]]
    [[ "$output" == *"NOT assumed to be v1"* ]]
}

@test "an up-to-date host reports nothing outstanding" {
    # Derived from VERSION, not written as a literal. A version bump should
    # break the tests that are about versions and no others, and hard-coding
    # "the current one" here makes every bump fail this for the wrong reason.
    newest=$(tr -d '[:space:]' < "$REPO/VERSION")
    write_state "guest_version=$newest" "node_version=$newest" \
                node_asserted=2026-08-25 node_verified=yes
    run_tool status --no-verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing. Both halves"* ]]
}

@test "a node behind its guest has console work outstanding" {
    write_state guest_version=2 node_version=1 node_asserted=2026-06-01 node_verified=yes
    run_tool status --no-verify
    [ "$status" -ne 0 ]
    [[ "$output" == *"console work outstanding"* ]]
    # The guest half of v2 is done, so it must not also be listed.
    [[ "$output" != *"re-run dejima-devbox-bootstrap from a v2 checkout"* ]]
}

@test "a guest behind its node is named as a restored snapshot" {
    # The one direction nobody does on purpose, and the only warning there is.
    write_state guest_version=1 node_version=2 node_asserted=2026-08-25 node_verified=yes
    run_tool status --no-verify
    [ "$status" -ne 0 ]
    [[ "$output" == *"guest is behind the node"* ]]
    [[ "$output" == *"restoring an old snapshot"* ]]
}

@test "both halves outstanding lists both" {
    write_state guest_version=1 node_version=1 node_asserted=2026-06-01 node_verified=yes
    run_tool status --no-verify
    [[ "$output" == *"console work outstanding"* ]]
    [[ "$output" == *"re-run dejima-devbox-bootstrap"* ]]
}

@test "an upgrade needing a snapshot says so in status, not only in the note" {
    write_state guest_version=1 node_version=1
    run_tool status --no-verify
    [[ "$output" == *"snapshot: REQUIRED"* ]]
}

# --- not claiming to know what it cannot ------------------------------------

@test "the installed copy admits it cannot see newer versions" {
    # An installed v1 tool would otherwise report "up to date" with total
    # confidence, having never heard of v2. This is the same failure as reading
    # a timeout as a pass.
    share="$BATS_TEST_TMPDIR/share"
    mkdir -p "$share/upgrades" "$BATS_TEST_TMPDIR/sbin"
    cp "$REPO"/upgrades/0001-*.md "$share/upgrades/"
    cp "$TOOL" "$BATS_TEST_TMPDIR/sbin/dejima-devbox-upgrade"
    write_state guest_version=1 node_version=1
    CONF_DIR="$STATE_DIR" SHARE_DIR="$share" \
        run "$BATS_TEST_TMPDIR/sbin/dejima-devbox-upgrade" status --no-verify
    [[ "$output" == *"installed copy"* ]]
    [[ "$output" == *"cannot tell you about a version"* ]]
}

@test "with no notes reachable it refuses rather than reporting a clean run" {
    # A copy that can find no notes knows nothing about any version. The one
    # answer it must never give is the reassuring one.
    lonely="$BATS_TEST_TMPDIR/lonely"
    mkdir -p "$lonely"
    cp "$TOOL" "$lonely/dejima-devbox-upgrade"
    write_state guest_version=1 node_version=1
    CONF_DIR="$STATE_DIR" SHARE_DIR="$BATS_TEST_TMPDIR/absent" \
        run "$lonely/dejima-devbox-upgrade" status --no-verify
    [ "$status" -eq 2 ]
    [[ "$output" == *"no upgrade notes found"* ]]
}

# --- not recording a claim the machine contradicts --------------------------

@test "mark-node refuses when the check for that upgrade fails" {
    stub_audit 1
    write_state guest_version=2
    run_tool mark-node 2
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to record"* ]]
    # And nothing was written.
    ! grep -q '^node_version=' "$STATE_DIR/state"
}

@test "mark-node records when the check passes, and says it verified" {
    stub_audit 0
    write_state guest_version=2
    run_tool mark-node 2
    [ "$status" -eq 0 ]
    grep -q '^node_version=2$' "$STATE_DIR/state"
    grep -q '^node_verified=yes$' "$STATE_DIR/state"
}

@test "--force records the claim but marks it unverified" {
    # Kept because a broken network makes some checks unreadable, and refusing
    # outright would only teach people to edit the state file by hand.
    stub_audit 1
    write_state guest_version=2
    run_tool mark-node 2 --force
    [ "$status" -eq 0 ]
    grep -q '^node_version=2$' "$STATE_DIR/state"
    grep -q '^node_verified=no$' "$STATE_DIR/state"
}

@test "a missing verify command is not reported as a failed check" {
    # A check that could not run has not found anything. Calling that a failure
    # trains an operator to ignore the word.
    #
    # The tool has to be genuinely alone for this: run from the repository it
    # finds dejima-devbox-audit beside itself and uses it, which is the whole
    # point of the fallback and the reason this test cannot just rely on $PATH.
    lonely="$BATS_TEST_TMPDIR/alone"
    mkdir -p "$lonely/bin"
    cp "$TOOL" "$lonely/bin/dejima-devbox-upgrade"
    ln -s "$REPO/upgrades" "$lonely/upgrades"
    write_state guest_version=2
    CONF_DIR="$STATE_DIR" run "$lonely/bin/dejima-devbox-upgrade" mark-node 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"cannot check"* ]]
    grep -q '^node_verified=no$' "$STATE_DIR/state"
}

@test "the verify command is found beside the tool when it is not on PATH" {
    # The sister project shipped the inverse of this and it found a real
    # runner: the notes say to run from a checkout, and a PATH-only lookup
    # could not find the program doing the looking.
    write_state guest_version=2
    stub_audit 0
    # No stub on PATH this time - the sibling in bin/ must be what answers.
    PATH="$BATS_TEST_TMPDIR/empty:$PATH" CONF_DIR="$STATE_DIR" run "$TOOL" mark-node 2
    [[ "$output" != *"is not installed here"* ]]
}

@test "a check that could not tell is recorded, not refused" {
    # Exit 2 means "could not determine". Collapsing it into "not in force"
    # would tell an operator their console work is missing on the strength of
    # a check that never ran.
    stub_audit 2
    write_state guest_version=2
    run_tool mark-node 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not tell"* ]]
    [[ "$output" != *"refusing to record"* ]]
    grep -q '^node_verified=no$' "$STATE_DIR/state"
}

@test "an unrecorded upgrade whose check passes is not reported as work to do" {
    # Restoring a snapshot older than the console work leaves the rules on the
    # node and takes the record with the guest. Reporting that as work to do
    # sends an operator to redo something already done.
    stub_audit 0
    write_state guest_version=2
    run_tool status
    # v2 declares a check and it passes, so it is not work to do.
    [[ "$output" == *"NOT RECORDED, but its check passes"* ]]
    # v3 declares no check, so it stays plainly outstanding. Both branches in
    # one run, which is also why this cannot assert the absence of that phrase.
    [[ "$output" == *"console work outstanding"* ]]
}

@test "status contradicts a recorded claim the machine no longer supports" {
    # An assertion true in June and false now is a rule somebody removed. Better
    # found by a timer than by an incident.
    stub_audit 1
    write_state guest_version=2 node_version=2 node_asserted=2026-06-01 node_verified=yes
    run_tool status
    [ "$status" -ne 0 ]
    [[ "$output" == *FAILED* ]]
    [[ "$output" == *"whatever the state file says"* ]]
}

@test "status confirms a recorded claim the machine still supports" {
    stub_audit 0
    newest=$(tr -d '[:space:]' < "$REPO/VERSION")
    write_state "guest_version=$newest" "node_version=$newest" \
                node_asserted=2026-08-25 node_verified=yes
    run_tool status
    [ "$status" -eq 0 ]
    [[ "$output" == *"in force"* ]]
}

# --- the notes themselves ---------------------------------------------------

@test "every version from 1 to VERSION has an upgrade note" {
    # A missing note and a note saying "nothing to do" are the same thing to
    # someone who has to go looking, so absence is not allowed to mean either.
    newest=$(tr -d '[:space:]' < "$REPO/VERSION")
    for v in $(seq 1 "$newest"); do
        ls "$REPO/upgrades/$(printf '%04d' "$v")"-*.md >/dev/null 2>&1 \
            || { echo "no upgrade note for v$v"; false; }
    done
}

@test "every note's version field matches its filename" {
    for f in "$REPO"/upgrades/0*.md; do
        from_name=$(basename "$f" | sed 's/^0*\([0-9][0-9]*\)-.*/\1/')
        from_head=$(sed -n '/^---$/,/^---$/p' "$f" | sed -n 's/^version: //p' | head -1)
        [ "$from_name" = "$from_head" ] \
            || { echo "$f: filename says $from_name, header says $from_head"; false; }
    done
}

@test "every note declares the keys the tool reads" {
    for f in "$REPO"/upgrades/0*.md; do
        for k in version title layers snapshot; do
            sed -n '/^---$/,/^---$/p' "$f" | grep -q "^$k: " \
                || { echo "$f: no '$k' in the header"; false; }
        done
    done
}

@test "a note with no guest step does not invoke the tool as if it were installed" {
    # dejima-devbox-upgrade arrives WITH a version, installed by bootstrap. A
    # note whose layers do not include 'guest' runs no bootstrap, so on the
    # machine being upgraded the tool is not on $PATH and will not be put there
    # by that note - it has to be run from a checkout. Telling an operator
    # otherwise gives them a command that cannot work on the host it was written
    # for.
    for f in "$REPO"/upgrades/0*.md; do
        layers=$(sed -n '/^---$/,/^---$/p' "$f" | sed -n 's/^layers: //p')
        case " $layers " in *" guest "*) continue ;; esac
        ! grep -qE '^[[:space:]]*(sudo )?dejima-devbox-upgrade ' "$f" \
            || { echo "$f: no guest step installs it, so commands must use ./bin/dejima-devbox-upgrade"; false; }
    done
}

@test "VERSION is a bare integer, since the scheme has no minor part" {
    run cat "$REPO/VERSION"
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "the newest note matches VERSION, so a bump cannot be half-done" {
    newest_note=$(ls "$REPO"/upgrades/0*.md | sed -n 's/.*\/0*\([0-9][0-9]*\)-.*/\1/p' | sort -n | tail -1)
    [ "$newest_note" = "$(tr -d '[:space:]' < "$REPO/VERSION")" ]
}
