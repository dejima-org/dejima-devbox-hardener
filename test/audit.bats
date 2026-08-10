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
    positive_controls_ok() { return 0; }
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
