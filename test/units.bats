#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# The systemd units, checked against where bootstrap actually puts things.
#
# These exist because the failure they guard has no symptom worth the name. A
# unit naming a program that is not there fails with 203/EXEC on every start,
# and for a timer that means the firewall silently stops being re-checked: no
# error anyone sees, nothing different on the box, and a host that looks
# configured while verifying nothing at all.
#
# In the sister repository a timer shipped that way and had never once worked
# on any host. The unit said /usr/local/bin and the installer used
# /usr/local/sbin, and nothing compared the two.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    T="$BATS_TEST_TMPDIR"
}

@test "no unit hard-codes a path to a program bootstrap places" {
    # Assert there is something to check first. Without this the test passes
    # when systemd/ is empty or absent, because grep's own failure to open a
    # file also produces a non-zero status - a green test asserting nothing.
    units=("$REPO"/systemd/*.service)
    [ -f "${units[0]}" ] || { echo "no units to check"; false; }

    # The path belongs to bootstrap. Written down a second time it can only
    # agree by luck, and in the sister repository it did not.
    run grep -nE '^Exec(Start|Stop)=/(usr|opt|bin|sbin)' "${units[@]}"
    [ "$status" -ne 0 ]
}

@test "every unit's ExecStart resolves to the directory bootstrap uses" {
    # This repository has no install.sh by design, so the value is read from
    # the one entry point instead. Copying this test unchanged would have made
    # it pass by reading a file that does not exist.
    bin=$(sed -n 's|^BIN_DIR=${BIN_DIR:-\(.*\)}|\1|p' "$REPO/bin/dejima-devbox-bootstrap")
    [ -n "$bin" ]
    for u in "$REPO"/systemd/*.service; do
        exe=$(sed -n 's|^ExecStart=\([^ ]*\).*|\1|p' "$u" | head -1)
        [ -n "$exe" ]
        # After substitution it must name a program this repository ships.
        resolved="${exe/@@BIN_DIR@@/$bin}"
        [ "$resolved" != "$exe" ] || { echo "$u: ExecStart is not templated: $exe"; false; }
        prog="${resolved##*/}"
        [ -f "$REPO/bin/$prog" ] || { echo "$u: names $prog, which bin/ does not ship"; false; }
    done
}

@test "bootstrap substitutes the marker rather than copying it through" {
    grep -q '@@BIN_DIR@@' "$REPO/bin/dejima-devbox-bootstrap"
    # And refuses to finish if what it wrote is not executable.
    grep -q 'which is not executable' "$REPO/bin/dejima-devbox-bootstrap"
}

@test "every program in bin/ is executable" {
    # Not theoretical: bin/dejima-devbox-clone was committed without the bit
    # and every caller got 126 with a message about permissions rather than
    # about the program. bootstrap installs the audit with `install -m 0755`,
    # which hides this for that one file and for no other - the rest are run
    # straight out of the checkout.
    progs=("$REPO"/bin/*)
    [ -f "${progs[0]}" ] || { echo "no programs in bin/"; false; }
    for p in "${progs[@]}"; do
        [ -x "$p" ] || { echo "not executable: $p"; false; }
    done
}
