#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# The source of dejima, and nothing beyond it.
#
# Two things are being pinned here. The first is that an existing directory is
# never touched: this runs as the operator, in the operator's home, against a
# path they may already be using, and a program that fetches source is not one
# anybody expects to modify a checkout they have been working in.
#
# The second is the line between the two projects. This clones; dejima's own
# install.sh installs. A test asserting that nothing under the account was
# written is the only thing that keeps that from drifting the first time it
# looks convenient to "just run install.sh while we are here".
#
# No network. The fixture is a real repository on disk, cloned over file://,
# so these run anywhere and test the actual git invocation rather than a stub.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CLONE="$REPO/bin/dejima-devbox-clone"

    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    # A repository to clone from. -c rather than `git config`, so this does not
    # depend on an identity being set wherever the suite happens to run.
    UPSTREAM="$BATS_TEST_TMPDIR/upstream"
    mkdir -p "$UPSTREAM"
    git -C "$UPSTREAM" init -q -b main
    printf 'dejima\n' > "$UPSTREAM/README.md"
    git -C "$UPSTREAM" add README.md
    git -C "$UPSTREAM" \
        -c user.email=nobody@example.invalid -c user.name=nobody \
        commit -q -m "first"
    export DEJIMA_URL="file://$UPSTREAM"
}

@test "it clones into ~/dejima" {
    run "$CLONE"
    [ "$status" -eq 0 ]
    [ -f "$HOME/dejima/README.md" ]
}

@test "the directory is taken from DEJIMA_DIR when it is set" {
    # bootstrap sets this rather than relying on HOME, because it runs as root
    # and one preserved environment away from cloning into /root.
    DEJIMA_DIR="$BATS_TEST_TMPDIR/elsewhere" run "$CLONE"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/elsewhere/README.md" ]
    [ ! -e "$HOME/dejima" ]
}

@test "the url can be given as an argument" {
    unset DEJIMA_URL
    run "$CLONE" "file://$UPSTREAM"
    [ "$status" -eq 0 ]
    [ -f "$HOME/dejima/README.md" ]
}

@test "a second run leaves the checkout alone rather than pulling into it" {
    run "$CLONE"
    [ "$status" -eq 0 ]
    printf 'work in progress\n' > "$HOME/dejima/uncommitted"

    run "$CLONE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already at"* ]]
    # The point of the test. A pull, a reset or a re-clone would take this.
    [ -f "$HOME/dejima/uncommitted" ]
}

@test "a directory that is not a checkout is refused, not cloned over" {
    mkdir -p "$HOME/dejima"
    printf 'something of mine\n' > "$HOME/dejima/notes.txt"
    run "$CLONE"
    [ "$status" -ne 0 ]
    [ -f "$HOME/dejima/notes.txt" ]
    [ ! -e "$HOME/dejima/README.md" ]
}

@test "an empty directory is not a conflict" {
    # Someone who made the directory first meant this, and git clones into one.
    mkdir -p "$HOME/dejima"
    run "$CLONE"
    [ "$status" -eq 0 ]
    [ -f "$HOME/dejima/README.md" ]
}

@test "a url that does not resolve fails loudly rather than leaving a stub" {
    DEJIMA_URL="file://$BATS_TEST_TMPDIR/no-such-repo" run "$CLONE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not clone"* ]]
}

@test "it installs nothing into the account it clones for" {
    # The boundary between the two projects. dejima's install.sh writes all
    # three of these, and it is dejima's to run.
    run "$CLONE"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.claude" ]
    [ ! -e "$HOME/.local/bin" ]
    [ ! -e "$HOME/.config/dejima" ]
}

# --- the handoff ------------------------------------------------------------
#
# Text assertions, which are weak, and worth having anyway: the operator is
# left holding a step this tool deliberately does not take, and a handoff that
# stops mentioning it strands them with a checkout and no reason to think
# anything else is needed.

@test "bootstrap tells the operator to run dejima's installer" {
    run grep -c "install.sh" "$REPO/bin/dejima-devbox-bootstrap"
    [ "$status" -eq 0 ]
}

@test "bootstrap tells the operator the harness comes before dejima" {
    # The other half of that handoff, and the one with nothing else pointing at
    # it. dejima needs a harness installed for the account and signed in, this
    # program arranges neither, and an operator who reads only its output
    # reaches the first session with a credential proxy holding nothing.
    grep -q 'harness' "$REPO/bin/dejima-devbox-bootstrap"
    grep -q '\.credentials\.json' "$REPO/bin/dejima-devbox-bootstrap"
}

@test "bootstrap does not clone into root's home" {
    # It runs under sudo. $HOME there is root's, so the target has to be
    # resolved from the account rather than inherited.
    grep -q 'getent passwd' "$REPO/bin/dejima-devbox-bootstrap"
    run grep -nE 'DEJIMA_DIR="?\$HOME' "$REPO/bin/dejima-devbox-bootstrap"
    [ "$status" -ne 0 ]
}
