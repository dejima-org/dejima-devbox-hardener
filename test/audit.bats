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
    # The two IPv6 functions that touch the network, stubbed to the contained
    # answer for the same reason default_gateway is: every test would otherwise
    # ping the segment it happens to be running on.
    #
    # Their caller, ipv6_verdict, is deliberately NOT stubbed - see the note
    # below on positive_controls_ok for what that mistake looks like.
    ipv6_routable_addr() { printf ''; }
    ipv6_neighbour_replies() { printf '0\n'; }
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

# --- the other address family ------------------------------------------------
#
# The v4 checks above cannot see this at all: a guest reaching the LAN over IPv6
# has an unreachable v4 gateway and a reachable forge, which is exactly what a
# pass looks like.

@test "a global IPv6 address is a failure on its own, with no probe needed" {
    # It got there by SLAAC or DHCPv6, so an advertisement reached this guest and
    # a reply left it. That is the node not dropping v6, evidenced rather than
    # inferred.
    ipv6_routable_addr() { printf '2001:db8::5/64\n'; }
    run ipv6_verdict
    [ "$output" = FAIL ]
}

@test "a link-local address alone is not a failure, because it is always there" {
    # The kernel brings one up whether or not anything routes v6. Reading it as
    # reach would fail every correctly contained VM, which is why the address
    # check is scoped to global.
    run ipv6_verdict
    [ "$output" = PASS ]
}

@test "a neighbour answering on the link fails even with no v6 address here" {
    # The case a v4 reading misses entirely: nothing routes v6, every host on the
    # segment is still reachable at fe80:: and answering for it.
    ipv6_neighbour_replies() { printf '2\n'; }
    run ipv6_verdict
    [ "$output" = FAIL ]
}

@test "our own reply to our own multicast is not a neighbour" {
    # We answer ff02::1 too. Counting that reports every contained VM as a
    # failure, and it is the first thing this probe gets wrong if left alone.
    out='64 bytes from fe80::1%eth0: icmp_seq=1 ttl=64 time=0.052 ms'
    run ipv6_replies_from_others "$out" 'fe80::1'
    [ "$output" = 0 ]
}

@test "a neighbour's reply alongside our own is counted" {
    out='64 bytes from fe80::1%eth0: icmp_seq=1 ttl=64 time=0.052 ms
64 bytes from fe80::99%eth0: icmp_seq=1 ttl=64 time=1.21 ms (DUP!)'
    run ipv6_replies_from_others "$out" 'fe80::1'
    [ "$output" = 1 ]
}

@test "silence from the whole segment counts nobody" {
    run ipv6_replies_from_others '' 'fe80::1'
    [ "$output" = 0 ]
}

@test "a v6 failure fails the whole reach check even when the v4 half passes" {
    gateway_verdict() { printf 'PASS\n'; }
    ipv6_neighbour_replies() { printf '1\n'; }
    run cmd_reach
    [ "$status" -ne 0 ]
    [[ "$output" == *FAIL* ]]
}

@test "an INDETERMINATE v4 half is not overwritten by a v6 failure" {
    # Both are non-passes and both are reported, but INDETERMINATE is the more
    # specific thing to have said about the v4 half and survives as the verdict.
    gateway_verdict() { printf 'INDETERMINATE\n'; }
    ipv6_neighbour_replies() { printf '1\n'; }
    run cmd_reach
    [ "$status" -ne 0 ]
    [[ "$output" == *INDETERMINATE* ]]
}

@test "the v6 remedy points at the node, not at a sysctl in the guest" {
    # Someone reading this failure will reach for disable_ipv6 first. It is the
    # wrong layer for the same reason the rest of the firewall is not in here.
    gateway_verdict() { printf 'PASS\n'; }
    ipv6_neighbour_replies() { printf '1\n'; }
    run cmd_reach
    [[ "$output" == *guest* ]]
}

@test "a probe that could not run is indeterminate, not a pass" {
    # No ping installed, or no interface to ask on. Nobody answered because
    # nobody was asked, and the two are not the same reading.
    ipv6_neighbour_replies() { return 1; }
    run ipv6_verdict
    [ "$output" = INDETERMINATE ]
}

@test "an unrunnable probe still fails a host that has a global v6 address" {
    # The address needs no probe: it is evidence rather than inference, so the
    # answer is definite even where nothing could be sent.
    ipv6_routable_addr() { printf '2001:db8::5/64\n'; }
    ipv6_neighbour_replies() { return 1; }
    run ipv6_verdict
    [ "$output" = FAIL ]
}

@test "an unrunnable v6 probe fails the reach check rather than passing it" {
    gateway_verdict() { printf 'PASS\n'; }
    ipv6_neighbour_replies() { return 1; }
    run cmd_reach
    [ "$status" -ne 0 ]
    [[ "$output" == *INDETERMINATE* ]]
}

@test "an unrunnable v6 probe names the package that would fix it" {
    gateway_verdict() { printf 'PASS\n'; }
    ipv6_neighbour_replies() { return 1; }
    run cmd_reach
    [[ "$output" == *iputils-ping* ]]
}

@test "a v6 FAIL outranks a v6-probe INDETERMINATE for the reported verdict" {
    # Both are non-passes, but FAIL is definite and INDETERMINATE is not, so a
    # run that found a neighbour must not be softened by anything.
    gateway_verdict() { printf 'PASS\n'; }
    ipv6_neighbour_replies() { printf '1\n'; }
    run cmd_reach
    [[ "$output" == *FAIL* ]]
}

# --- radius report ----------------------------------------------------------
#
# This one inventories the box rather than the network, and the distinction is
# the whole reason it is allowed to exist. A list of other hosts would describe
# topology unobtainable from here without loud scanning. An inventory of this
# machine describes a machine the attacker is already standing on, and reveals
# nothing a single find would not.

@test "the radius report never prints the contents of a credential" {
    HOME="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.ssh"
    printf 'SUPERSECRETKEYMATERIAL\n' > "$HOME/.ssh/id_ed25519"
    chmod 600 "$HOME/.ssh/id_ed25519"
    run cmd_radius
    [[ "$output" != *SUPERSECRETKEYMATERIAL* ]]
    [[ "$output" == *id_ed25519* ]]
}

@test "a public key is not reported as a credential" {
    HOME="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.ssh"
    printf 'ssh-ed25519 AAAA nobody@example\n' > "$HOME/.ssh/id_ed25519.pub"
    printf 'private\n' > "$HOME/.ssh/id_ed25519"
    run cmd_radius
    # Both halves. Without the second this passes on empty output, which is
    # what it would have done against a cmd_radius that did not exist.
    [[ "$output" != *id_ed25519.pub* ]]
    [[ "$output" == *id_ed25519* ]]
}

@test "the radius report does not change the exit status" {
    # It describes choices, not faults. Only reachability carries the status.
    HOME="$BATS_TEST_TMPDIR"
    run cmd_radius
    [ "$status" -eq 0 ]
}

@test "docker group membership is reported as a fact, not corrected" {
    HOME="$BATS_TEST_TMPDIR"
    id() { printf 'uid=1000(dev) gid=1000(dev) groups=1000(dev),109(docker)\n'; }
    run cmd_radius
    [[ "$output" == *"root-equivalent"* ]]
}

@test "no docker group is reported too, rather than left silent" {
    HOME="$BATS_TEST_TMPDIR"
    id() { printf 'uid=1000(dev) gid=1000(dev) groups=1000(dev)\n'; }
    run cmd_radius
    [[ "$output" == *"not in the docker group"* ]]
}

@test "the radius report runs to its end rather than stopping quietly" {
    # It stopped halfway once: dpkg-query exits non-zero when no kernel package
    # matches, and under set -e with pipefail that killed the function mid-
    # report. Nothing was printed about it. The report simply ended, which on a
    # tool whose job is to tell you what you are exposed to is the worst
    # available failure. Assert the last section, not just the first.
    HOME="$BATS_TEST_TMPDIR"
    run cmd_radius
    [ "$status" -eq 0 ]
    [[ "$output" == *"Credentials"* ]]
    [[ "$output" == *"Group membership"* ]]
    [[ "$output" == *"Kernel"* ]]
    # The last line the report prints after the command that once killed it.
    # Both branches of the kernel check print it, so it is not a claim about
    # what dpkg holds - only that the function got past dpkg-query.
    [[ "$output" == *"newest installed"* ]]
}

# --- addressing mode and lease health ---------------------------------------
#
# The spec asked for this and the first implementation left it out. It matters
# because it is the one failure in this design that is invisible for up to a
# full lease time: a DHCP guest behind these rules renews through a path the
# firewall may be dropping, nothing breaks at boot, and the VM falls off the
# network much later looking nothing like a firewall rule.

@test "a static interface is reported as static" {
    INTERFACES_FILE="$BATS_TEST_TMPDIR/interfaces"
    printf 'iface ens18 inet static\n  address 192.0.2.5/24\n' > "$INTERFACES_FILE"
    run addressing_mode
    [ "$output" = static ]
}

@test "a dhcp interface is reported as dhcp" {
    INTERFACES_FILE="$BATS_TEST_TMPDIR/interfaces"
    printf 'iface ens18 inet dhcp\n' > "$INTERFACES_FILE"
    run addressing_mode
    [ "$output" = dhcp ]
}

@test "static wins over a stale lease left behind by an earlier dhcp life" {
    # A host pinned by dejima-devbox-static-ip keeps its old lease files. If
    # those decided the answer, every pinned host would be told it needs DHCP
    # rules it does not need.
    INTERFACES_FILE="$BATS_TEST_TMPDIR/interfaces"
    printf 'iface ens18 inet static\n' > "$INTERFACES_FILE"
    lease_file() { printf '%s\n' "$BATS_TEST_TMPDIR/old.leases"; }
    printf 'lease {\n  expire 0 2020/01/01 00:00:00;\n}\n' > "$BATS_TEST_TMPDIR/old.leases"
    run addressing_mode
    [ "$output" = static ]
}

@test "neither is reported as unknown rather than guessed" {
    INTERFACES_FILE="$BATS_TEST_TMPDIR/none"
    lease_file() { return 1; }
    run addressing_mode
    [ "$output" = unknown ]
}

@test "a lease already past its renewal time is reported as not renewing" {
    INTERFACES_FILE="$BATS_TEST_TMPDIR/interfaces"
    printf 'iface ens18 inet dhcp\n' > "$INTERFACES_FILE"
    # Not $f: cmd_radius declares `local f`, which shadows it and made this
    # stub return an empty path. A fixture variable a function might shadow is
    # a trap; give it a name nothing else would pick.
    fixture_lease="$BATS_TEST_TMPDIR/cur.leases"
    lease_file() { printf '%s\n' "$fixture_lease"; }
    past=$(date -u -d '2 hours ago' '+%Y/%m/%d %H:%M:%S')
    future=$(date -u -d '6 hours' '+%Y/%m/%d %H:%M:%S')
    printf 'lease {\n  renew 0 %s;\n  expire 0 %s;\n}\n' "$past" "$future" > "$fixture_lease"
    touch -d '3 hours ago' "$fixture_lease"
    run cmd_radius
    [[ "$output" == *"NOT RENEWING"* ]]
}

@test "a lease still inside its renewal window is not reported as failing" {
    INTERFACES_FILE="$BATS_TEST_TMPDIR/interfaces"
    printf 'iface ens18 inet dhcp\n' > "$INTERFACES_FILE"
    fixture_lease="$BATS_TEST_TMPDIR/cur.leases"
    lease_file() { printf '%s\n' "$fixture_lease"; }
    future=$(date -u -d '6 hours' '+%Y/%m/%d %H:%M:%S')
    later=$(date -u -d '12 hours' '+%Y/%m/%d %H:%M:%S')
    printf 'lease {\n  renew 0 %s;\n  expire 0 %s;\n}\n' "$future" "$later" > "$fixture_lease"
    run cmd_radius
    # Both halves. Asserting only the absence of the warning passes on a
    # report that says nothing about leases at all, which is how this test
    # went green before the feature existed.
    [[ "$output" == *"Addressing"* ]]
    [[ "$output" != *"NOT RENEWING"* ]]
}

@test "an unparseable lease file does not take the report down with it" {
    INTERFACES_FILE="$BATS_TEST_TMPDIR/interfaces"
    printf 'iface ens18 inet dhcp\n' > "$INTERFACES_FILE"
    fixture_lease="$BATS_TEST_TMPDIR/junk.leases"
    lease_file() { printf '%s\n' "$fixture_lease"; }
    printf 'this is not a lease\n' > "$fixture_lease"
    run cmd_radius
    [ "$status" -eq 0 ]
    [[ "$output" == *"newest installed"* ]]
}

@test "the credential that cannot be moved off the box is inventoried" {
    # dejima keeps this one out of the container on purpose, so an escape onto
    # the devbox is the step that reaches it. Not the only thing here worth
    # taking, but a standing capability rather than a copy of data, and at a
    # known path - so a radius report that lists SSH keys and omits it is
    # missing the one an attacker would look for first.
    HOME="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.claude"
    printf 'TOKENMATERIAL\n' > "$HOME/.claude/.credentials.json"
    run cmd_radius
    [[ "$output" == *".credentials.json"* ]]
    [[ "$output" != *TOKENMATERIAL* ]]
    [[ "$output" == *"cannot be moved off"* ]]
}

# --- kernel currency --------------------------------------------------------
#
# A false "reboot pending" is worse than it sounds. It is the one line in the
# report an operator is expected to act on, so a version of it that is wrong on
# ordinary hosts teaches them to scroll past the whole section.

@test "the unsigned image package is not read as a different kernel" {
    # Debian's signed image is linux-image-<version> and the unsigned one is
    # linux-image-<version>-unsigned. uname prints neither suffix, so comparing
    # the bare package name reported a pending reboot on every host running an
    # unsigned image, permanently, whatever it booted.
    dpkg-query() { printf 'ii  linux-image-6.12.101+deb13-amd64-unsigned\n'; }
    run newest_kernel
    [ "$output" = "6.12.101+deb13-amd64" ]
}

@test "a kernel removed but not purged does not count as installed" {
    # dpkg-query lists rc packages too. Counting one would announce a reboot
    # into a kernel that is not on the disk.
    dpkg-query() {
        printf 'ii  linux-image-6.1.0-13-amd64\nrc  linux-image-6.12.101+deb13-amd64\n'
    }
    run newest_kernel
    [ "$output" = "6.1.0-13-amd64" ]
}

@test "the newest of several installed kernels wins" {
    dpkg-query() {
        printf 'ii  linux-image-6.1.0-13-amd64\nii  linux-image-6.12.101+deb13-amd64\n'
    }
    run newest_kernel
    [ "$output" = "6.12.101+deb13-amd64" ]
}

@test "no packaged kernel is reported as unanswered, not as up to date" {
    dpkg-query() { return 1; }
    HOME="$BATS_TEST_TMPDIR"
    run cmd_radius
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not tell"* ]]
    [[ "$output" != *"reboot pending"* ]]
}

@test "a running kernel matching the newest reports no pending reboot" {
    HOME="$BATS_TEST_TMPDIR"
    newest_kernel() { uname -r; }
    run cmd_radius
    [[ "$output" == *"reboot pending:   no"* ]]
}

@test "a running kernel behind the newest reports one" {
    HOME="$BATS_TEST_TMPDIR"
    newest_kernel() { printf '99.0.0-amd64\n'; }
    run cmd_radius
    [[ "$output" == *"reboot pending:   YES"* ]]
}

# --- wrong machine ----------------------------------------------------------

@test "running in a container says so before reporting anything" {
    in_container() { return 0; }
    run main radius
    [[ "$output" == *"container, not a devbox"* ]]
}

@test "the warning comes before the findings, not after them" {
    # After the report it is a footnote on conclusions already drawn.
    in_container() { return 0; }
    run main radius
    warn=$(printf '%s\n' "$output" | grep -n "container, not a devbox" | head -1 | cut -d: -f1)
    first=$(printf '%s\n' "$output" | grep -n "What root on this VM would get" | head -1 | cut -d: -f1)
    [ -n "$warn" ] && [ -n "$first" ]
    [ "$warn" -lt "$first" ]
}

@test "it warns rather than refusing, so a deliberate run still works" {
    in_container() { return 0; }
    run main radius
    [ "$status" -eq 0 ]
    [[ "$output" == *"What root on this VM would get"* ]]
}

@test "on a devbox the banner does not appear" {
    # Matched on the banner's own wording, not on the word "container": the
    # report says that legitimately in several places, and a test keyed to it
    # would fail for reasons that have nothing to do with this.
    in_container() { return 1; }
    HOME="$BATS_TEST_TMPDIR"
    run main radius
    [[ "$output" != *"this looks like a container"* ]]
    [[ "$output" == *"What root on this VM would get"* ]]
}

# --- whose home is inventoried ----------------------------------------------
#
# The radius report runs as root, from a timer or under sudo, where $HOME is
# root's. Everything it is about lives in the account that runs dejima. Getting
# this wrong does not print an error - it prints "none found", on a box full of
# credentials.

@test "the account bootstrap recorded decides which home is inventoried" {
    CONF_DIR="$BATS_TEST_TMPDIR/conf"; mkdir -p "$CONF_DIR"
    printf 'forge_host=forge.example.invalid\ndevbox_user=dev\n' > "$CONF_DIR/config"
    getent() { printf 'dev:x:1000:1000::/home/dev:/bin/bash\n'; }
    run devbox_home
    [ "$output" = /home/dev ]
}

@test "no recorded account falls back to this process's home" {
    # A host bootstrapped before the key existed reports what it always did,
    # rather than this guessing at /home/*.
    CONF_DIR="$BATS_TEST_TMPDIR/conf"; mkdir -p "$CONF_DIR"
    printf 'forge_host=forge.example.invalid\n' > "$CONF_DIR/config"
    HOME=/home/whoever
    run devbox_home
    [ "$output" = /home/whoever ]
}

@test "a recorded account that no longer exists falls back rather than emptying" {
    CONF_DIR="$BATS_TEST_TMPDIR/conf"; mkdir -p "$CONF_DIR"
    printf 'devbox_user=deleted\n' > "$CONF_DIR/config"
    getent() { return 2; }
    HOME=/home/whoever
    run devbox_home
    [ "$output" = /home/whoever ]
}

@test "the report inventories that account's credentials, not root's" {
    # The failure this exists for: root's home is empty on a devbox, so the
    # report read "none found" while the credentials sat one directory over.
    CONF_DIR="$BATS_TEST_TMPDIR/conf"; mkdir -p "$CONF_DIR"
    printf 'devbox_user=dev\n' > "$CONF_DIR/config"
    mkdir -p "$BATS_TEST_TMPDIR/dev/.ssh"
    printf 'private\n' > "$BATS_TEST_TMPDIR/dev/.ssh/id_ed25519"
    getent() { printf 'dev:x:1000:1000::%s:/bin/bash\n' "$BATS_TEST_TMPDIR/dev"; }
    HOME="$BATS_TEST_TMPDIR/root"; mkdir -p "$HOME"
    run cmd_radius
    [[ "$output" == *"$BATS_TEST_TMPDIR/dev/.ssh/id_ed25519"* ]]
    [[ "$output" != *"none found"* ]]
}
