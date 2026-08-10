#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# Runs on a real devbox and asserts against the real machine. Everything else
# in test/ runs anywhere and stubs what it needs; this file is the one that
# cannot be faked, and it is meaningless off the box.
#
# Gated on DEJIMA_DEVBOX being set rather than on detecting a devbox. A
# detector that guesses wrong skips silently, and a suite that passes by
# asserting nothing is worse than one that fails: the first is believed. The
# same reasoning put DEJIMA_CI_TIER in the sister repository, after a job
# landed on the wrong runner and quietly checked nothing.

setup() {
    [ "${DEJIMA_DEVBOX:-}" = 1 ] || skip "set DEJIMA_DEVBOX=1 to run this on a devbox"
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CONF=${CONF_DIR:-/etc/dejima-devbox}/config
}

forge() { sed -n 's/^forge_host=//p' "$CONF" | tail -1; }

@test "the gateway is unreachable, which is the whole point" {
    run "$REPO/bin/dejima-devbox-audit" reach
    [ "$status" -eq 0 ]
    [[ "$output" == *PASS* ]]
}

@test "the audit is installed where the unit expects to find it" {
    # 203/EXEC on every fire, with nothing anyone reads, is the failure this
    # guards. Resolve the unit's own ExecStart rather than assuming a path.
    exe=$(systemctl cat dejima-devbox-audit.service \
          | sed -n 's|^ExecStart=\([^ ]*\).*|\1|p' | head -1)
    [ -n "$exe" ]
    [ -x "$exe" ]
}

@test "the timer is active, so this keeps being checked" {
    run systemctl is-active dejima-devbox-audit.timer
    [ "$output" = active ]
}

@test "the timer runs reach and not the credential inventory" {
    # The radius report names credential paths. On a schedule that inventory
    # would accumulate in the journal, outliving the run and readable by
    # anything that later gets root.
    run systemctl cat dejima-devbox-audit.service
    [[ "$output" == *"dejima-devbox-audit reach"* ]]
    [[ "$output" != *"dejima-devbox-audit all"* ]]
}

@test "the forge is reachable on 443" {
    host=$(forge); [ -n "$host" ]
    run timeout 5 bash -c "exec 3<>/dev/tcp/$host/443"
    [ "$status" -eq 0 ]
}

@test "the forge is reachable on 22, which a CI runner never needed" {
    # A devbox pushes over SSH. Without the second forge rule this hangs
    # against the DROPs rather than failing, which reads as the forge being
    # down.
    host=$(forge); [ -n "$host" ]
    run timeout 5 bash -c "exec 3<>/dev/tcp/$host/22"
    [ "$status" -eq 0 ]
}

@test "the public internet is still reachable, so this is not just broken" {
    # Without this the gateway test above passes on a machine with no network
    # at all. PASS means contained; it must not also mean unplugged.
    run timeout 5 bash -c "exec 3<>/dev/tcp/deb.debian.org/80"
    [ "$status" -eq 0 ]
}
