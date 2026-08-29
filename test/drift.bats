#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# `drift` answers "what changed since somebody said this box was known good",
# and the ways it can be wrong are the ways every check in this repository can
# be wrong: reporting clean when it compared nothing, or reporting a finding
# that is an artefact of how it ran rather than of anything on the machine.
#
# Both are tested here, and the second is the one that would have shipped. Run
# without the privilege to read every watched path, the state comes back partial
# and diffs against a full baseline as a list of REMOVALS - which reads as an
# intruder deleting things. That is worse than a false pass, because it is a
# false alarm that looks exactly like the thing being looked for.
#
# The split follows audit.bats: cmd_drift is tested with drift_state stubbed, so
# what is under test is the comparison. drift_state is tested separately with
# drift_paths pointed at a scratch directory, so what is under test there is
# what it collects. Neither test lets the real /etc, systemctl or ss decide the
# outcome, because a suite whose result depends on which ports happened to be
# open is a suite nobody trusts twice.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    source "$REPO/bin/dejima-devbox-audit"
    BASELINE_DIR="$BATS_TEST_TMPDIR/lib"
    BASELINE="$BASELINE_DIR/baseline"
    # No tool is missing, nothing is unreadable, and dpkg finds nothing, unless
    # a test says otherwise. Each is the outside world; the diff is not.
    drift_missing() { printf ''; }
    drift_dpkg()    { printf ''; }
}

# A state of exactly these lines, as drift_state would have printed them.
#
# Through a file rather than a variable: a `local` in here is not in scope
# inside the function it defines, which fails at call time rather than at
# definition, with an error naming this line and not the test that broke.
stub_state() {
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/state.stub"
    drift_state() { cat "$BATS_TEST_TMPDIR/state.stub"; }
}

@test "no baseline is indeterminate, not clean" {
    # Nothing has been compared, which is not the same as nothing having
    # changed, and only one of those is safe to report.
    stub_state "FILE aaa /etc/one"
    run cmd_drift
    # 2, not merely non-zero: the upgrade tool reads this as "could not
    # determine" rather than "not in force".
    [ "$status" -eq 2 ]
    [[ "$output" == *INDETERMINATE* ]]
    [[ "$output" == *"no baseline"* ]]
}

@test "an unchanged box is clean" {
    stub_state "FILE aaa /etc/one" "UNIT foo.service"
    cmd_drift --accept
    run cmd_drift
    [ "$status" -eq 0 ]
    [[ "$output" == *CLEAN* ]]
}

@test "a new file is drift, and is shown" {
    stub_state "FILE aaa /etc/one"
    cmd_drift --accept
    stub_state "FILE aaa /etc/one" "FILE bbb /etc/two"
    run cmd_drift
    [ "$status" -ne 0 ]
    [[ "$output" == *DRIFT* ]]
    [[ "$output" == *"+ FILE bbb /etc/two"* ]]
}

@test "a removed file is drift too" {
    stub_state "FILE aaa /etc/one" "FILE bbb /etc/two"
    cmd_drift --accept
    stub_state "FILE aaa /etc/one"
    run cmd_drift
    [ "$status" -ne 0 ]
    [[ "$output" == *"- FILE bbb /etc/two"* ]]
}

@test "an edited file shows as both a removal and an addition" {
    # The hash is in the line, so an edit is not an update in place. Worth
    # pinning because it is what an operator will see and be confused by once.
    stub_state "FILE aaa /etc/one"
    cmd_drift --accept
    stub_state "FILE zzz /etc/one"
    run cmd_drift
    [[ "$output" == *"+ FILE zzz /etc/one"* ]]
    [[ "$output" == *"- FILE aaa /etc/one"* ]]
}

@test "a newly enabled unit is drift, which hashing files alone would miss" {
    # `systemctl enable` writes a symlink, and a symlink is not a regular file.
    stub_state "FILE aaa /etc/one"
    cmd_drift --accept
    stub_state "FILE aaa /etc/one" "UNIT backdoor.service"
    run cmd_drift
    [[ "$output" == *"+ UNIT backdoor.service"* ]]
}

@test "a newly open port is drift, which no file check would see at all" {
    stub_state "FILE aaa /etc/one"
    cmd_drift --accept
    stub_state "FILE aaa /etc/one" "PORT 0.0.0.0:4444"
    run cmd_drift
    [[ "$output" == *"+ PORT 0.0.0.0:4444"* ]]
}

# --- the failure that looks like the thing being looked for -----------------

@test "an unreadable path is indeterminate rather than a list of removals" {
    # This is the one that would have shipped. Running without root, the state
    # is partial and every file it could not read looks deleted.
    stub_state "FILE aaa /etc/one"
    cmd_drift --accept
    drift_state() { printf 'FILE aaa /etc/one\n'; echo "find: '/etc/ssl/private': Permission denied" >> "$DRIFT_ERRS"; }
    run cmd_drift
    [ "$status" -ne 0 ]
    [[ "$output" == *INDETERMINATE* ]]
    [[ "$output" == *"Run with sudo"* ]]
    [[ "$output" != *DRIFT* ]]
}

@test "dpkg finding a modified packaged file is drift on its own" {
    # Absolute rather than baselined: it needs no previous run to be meaningful,
    # so it must count even against a baseline that says everything is fine.
    stub_state "FILE aaa /etc/one"
    cmd_drift --accept
    drift_dpkg() { printf '??5??????   /usr/bin/ssh\n'; }
    run cmd_drift
    [ "$status" -ne 0 ]
    [[ "$output" == *"/usr/bin/ssh"* ]]
}

@test "a missing collector is recorded in the baseline it was absent from" {
    # Otherwise a baseline taken on a host without ss compares clean forever
    # against states that also lack PORT lines, and nobody learns that the
    # port half of this has never once run.
    drift_missing() { printf 'ss '; }
    stub_state "FILE aaa /etc/one"
    run cmd_drift --accept
    [[ "$output" == *"NOT COVERED"* ]]
    grep -q 'NOT COVERED' "$BASELINE"
}

@test "the baseline is not written where it would report itself" {
    # Under /etc it would appear in its own state, change every time it was
    # taken, and produce a finding on every run forever.
    case "$BASELINE_DIR" in /etc/*) echo "baseline lives under a watched path"; false ;; esac
    run drift_paths
    [[ "$output" != *"$BASELINE_DIR"* ]]
}

# --- what drift_state actually collects -------------------------------------

@test "drift_state hashes the files under the paths it is given" {
    scratch="$BATS_TEST_TMPDIR/scratch"
    mkdir -p "$scratch"
    echo hello > "$scratch/a"
    drift_paths() { printf '%s\n' "$scratch"; }
    DRIFT_ERRS="$BATS_TEST_TMPDIR/errs"; : > "$DRIFT_ERRS"
    run drift_state
    [[ "$output" == *"FILE "*"$scratch/a"* ]]
}

@test "a filename holding a backslash or a newline is still tagged FILE" {
    # sha256sum escapes those two: it prefixes the line with a backslash and
    # rewrites the name. That broke the tag, so the line went out untagged -
    # and the watcher counts changes by their tag, so a file with such a name
    # could change without appearing in the count the alert carries.
    #
    # A filename is attacker-chosen on a box under suspicion, which makes this
    # a gap somebody could pick rather than one they would have to stumble into.
    scratch="$BATS_TEST_TMPDIR/odd"
    mkdir -p "$scratch"
    printf 'x' > "$scratch/back\slash"
    printf 'y' > "$(printf '%s/new\nline' "$scratch")"
    drift_paths() { printf '%s\n' "$scratch"; }
    DRIFT_ERRS="$BATS_TEST_TMPDIR/errs"; : > "$DRIFT_ERRS"
    run drift_state
    [ "$(printf '%s\n' "$output" | grep -c '^FILE ')" -eq 2 ]
    [[ "$output" != *$'\n'[0-9a-f][0-9a-f]* ]]
}

@test "drift_state records what it could not read rather than dropping it" {
    scratch="$BATS_TEST_TMPDIR/locked"
    mkdir -p "$scratch/private"
    chmod 000 "$scratch/private"
    drift_paths() { printf '%s\n' "$scratch"; }
    DRIFT_ERRS="$BATS_TEST_TMPDIR/errs2"; : > "$DRIFT_ERRS"
    run drift_state
    chmod 755 "$scratch/private"
    [ -s "$DRIFT_ERRS" ]
}

# --- the state emitter, which is what a watcher on another machine reads -----

@test "--state prints the state and compares nothing" {
    # No baseline needed and none consulted: the watcher keeps that, because a
    # baseline kept here is one root here can rewrite, and root here is the
    # case being looked for.
    stub_state "FILE aaa /etc/one" "UNIT foo.service"
    run cmd_drift --state
    [ "$status" -eq 0 ]
    [[ "$output" == *"FILE aaa /etc/one"* ]]
    [[ "$output" == *"UNIT foo.service"* ]]
    [[ "$output" != *CLEAN* ]]
    [[ "$output" != *INDETERMINATE* ]]
}

@test "--state still refuses when the state would be partial" {
    # A watcher diffing a partial state against a full baseline sees a list of
    # removals and calls it an intruder. The refusal has to survive the emitter.
    stub_state "FILE aaa /etc/one"
    drift_state() { printf 'FILE aaa /etc/one\n'; echo "denied" >> "$DRIFT_ERRS"; }
    run cmd_drift --state
    [ "$status" -eq 2 ]
    [[ "$output" == *INDETERMINATE* ]]
}

@test "--state does not write a baseline" {
    stub_state "FILE aaa /etc/one"
    run cmd_drift --state
    [ ! -e "$BASELINE" ]
}

# --- exit status ------------------------------------------------------------

@test "all does not lose a drift finding behind a clean reach" {
    # Each subcommand carries its own status. Without collecting them, a box
    # with a planted unit file and a working firewall exits 0.
    cmd_radius() { return 0; }
    cmd_reach()  { return 0; }
    cmd_drift()  { return 1; }
    container_warning() { return 0; }
    run main all
    [ "$status" -ne 0 ]
}
