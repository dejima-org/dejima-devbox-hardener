#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# The audit's whole job is to distinguish "the firewall dropped it" from "no
# answer came back for some other reason". Those look identical from inside the
# VM, so the verdict has three states, and these tests pin all three.
#
# The one that matters most is INDETERMINATE. A check that reports a pass when
# it does not know is worse than no check, because it is believed.
#
# The program guards its own main, so these tests source it and redefine the
# two functions that touch the outside world. No fake binaries on PATH: the
# thing under test here is the decision, not the plumbing.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    source "$REPO/bin/dejima-devbox-audit"
    default_gateway() { printf '192.0.2.1\n'; }
    # positive_controls_ok is deliberately NOT stubbed here. Stubbing it in
    # setup shadowed the real function for the tests that exist to check it,
    # and they passed against the stub. Each test that needs it faked says so.
}

@test "a completed handshake on any probed port is a definite failure" {
    probe_tcp() { [ "$2" = 80 ] && printf 'open\n' || printf 'timeout\n'; }
    run gateway_verdict
    [ "$output" = FAIL ]
}

@test "a refusal is also a definite failure, because it proves arrival" {
    # A closed port still means the packet reached a live host and something
    # sent an answer back. Silently dropped is the only thing that passes.
    probe_tcp() { [ "$2" = 22 ] && printf 'answered\n' || printf 'timeout\n'; }
    run gateway_verdict
    [ "$output" = FAIL ]
}

@test "silence on every port, with the network known good, is a pass" {
    probe_tcp() { printf 'timeout\n'; }
    positive_controls_ok() { return 0; }
    run gateway_verdict
    [ "$output" = PASS ]
}

@test "silence with a failed positive control is indeterminate, never a pass" {
    probe_tcp() { printf 'timeout\n'; }
    positive_controls_ok() { return 1; }
    run gateway_verdict
    [ "$output" = INDETERMINATE ]
}

@test "an absent default route fails loudly rather than skipping the check" {
    default_gateway() { return 1; }
    probe_tcp() { printf 'timeout\n'; }
    run gateway_verdict
    [ "$status" -ne 0 ]
    [[ "$output" == *"no default route"* ]]
}

@test "port 53 is never probed, because the resolver exception may allow it" {
    # A rule working exactly as designed would otherwise read as a failure.
    for p in "${PROBE_PORTS[@]}"; do [ "$p" != 53 ]; done
}

# --- positive controls ------------------------------------------------------
#
# These are what make a timeout mean something. Without them the audit would be
# guessing which of the two causes it was looking at, and calling the guess a
# pass.

@test "the network is good when the forge answers on 443" {
    forge_host() { printf 'forge.example.invalid\n'; }
    resolve_ok() { return 1; }
    probe_tcp() { printf 'open\n'; }
    run positive_controls_ok
    [ "$status" -eq 0 ]
}

@test "resolution alone is enough, because it proves packets flow" {
    forge_host() { printf 'forge.example.invalid\n'; }
    resolve_ok() { return 0; }
    probe_tcp() { printf 'timeout\n'; }
    run positive_controls_ok
    [ "$status" -eq 0 ]
}

@test "the network is not good when nothing resolves and nothing answers" {
    forge_host() { printf 'forge.example.invalid\n'; }
    resolve_ok() { return 1; }
    probe_tcp() { printf 'timeout\n'; }
    run positive_controls_ok
    [ "$status" -ne 0 ]
}

@test "a missing forge_host is not good, rather than quietly good" {
    forge_host() { return 1; }
    run positive_controls_ok
    [ "$status" -ne 0 ]
}

# --- exit status ------------------------------------------------------------

@test "reach exits non-zero on FAIL" {
    gateway_verdict() { printf 'FAIL\n'; }
    run cmd_reach
    # Assert the verdict too. Without it this passes on status 127 from a
    # command that does not exist, which is how a test comes to assert nothing.
    [ "$status" -ne 0 ]
    [[ "$output" == *FAIL* ]]
}

@test "reach exits non-zero on INDETERMINATE, which must not read as a pass" {
    gateway_verdict() { printf 'INDETERMINATE\n'; }
    run cmd_reach
    [ "$status" -ne 0 ]
    [[ "$output" == *INDETERMINATE* ]]
}

@test "reach exits zero on PASS" {
    gateway_verdict() { printf 'PASS\n'; }
    run cmd_reach
    [ "$status" -eq 0 ]
}

@test "a FAIL says REJECT could be the cause, since the probe cannot tell" {
    gateway_verdict() { printf 'FAIL\n'; }
    run cmd_reach
    [[ "$output" == *REJECT* ]]
}
