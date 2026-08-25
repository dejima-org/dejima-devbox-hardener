---
version: 2
title: The LAN boundary gains IPv6 and the CGNAT range
layers: node guest
snapshot: required
verify-node: dejima-devbox-audit reach
---

# v2 — the LAN boundary gains IPv6 and the CGNAT range

Two rules on the hypervisor, one package and a re-run of bootstrap in the guest,
and a fresh snapshot. Budget twenty minutes, most of it waiting for the console.

**Do the node half first.** The guest half installs an audit that checks the
node half, and running it before the rules exist produces a `FAIL` that is
correct, alarming, and not about anything you did wrong.

## Why

The node firewall's outbound DROPs named IPv4 ranges only, so the control this
project exists to provide did not apply to IPv6 at all. Every Linux host brings
up an `fe80::` address on every interface whether or not anything routes v6, and
a daemon bound to `::` answers on it — so the machine beside your devbox was
reachable across the segment with all four DROPs in force, on a network with no
IPv6 in it. `dejima-devbox-audit reach` reported `PASS` throughout, because its
probe was `ip -4 route show default`.

The full argument is in
[the threat model](../docs/threat-model.md#the-lan-boundary-is-two-boundaries).
The short version: IPv6 has no RFC 1918, so the family is dropped whole rather
than enumerated.

## 1. Node — two rules in the Proxmox console

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

Add these two. They are rules 11 and 12 of
[the table in the runbook](../proxmox/README.md#build-the-group-once):

| # | Direction | Action | Protocol | Dest. port | Source / Dest |
| --- | --- | --- | --- | --- | --- |
| 11 | out | DROP | — | — | **Dest:** `100.64.0.0/10` |
| 12 | out | DROP | — | — | **Dest:** `::/0` |

**Both go at the bottom, below every existing rule.** The console inserts each
new rule at the *top* of the list, so a rule left where it lands sits above your
forge and resolver pinholes. These two are DROPs; put them above the pinholes
and the devbox stops reaching its forge. Drag each one down as you add it.

Nothing else in the group changes. You are appending, not re-entering.

**If the console rejects `::/0`**, enter four rules in rule 12's position
instead — `fe80::/10`, `fc00::/7`, `ff00::/8`, `2000::/3` — which cover the same
space. Prefer the single line where it is accepted: four entries are four
chances to enter three.

**Nothing to restart.** A security group edit applies to every VM referencing it
immediately. If you built the rules per-VM rather than as a group, you have this
to do on each VM, and building the group is worth doing while you are here.

### Check the node half landed

On the node:

```sh
sudo ip6tables -S | grep "tap<vmid>i0"
```

An IPv6 rule is compiled into `ip6tables` and is **absent from `iptables -S`**,
so the v4 table shows rule 12 missing whether it is there or not. Checking the
wrong table is the most likely way to conclude this worked when it did not.

## 2. Guest — the package, then bootstrap

```sh
sudo apt-get install -y iputils-ping
```

New dependency. The audit's IPv6 check asks the segment who is there and needs
`ping` to do it; without it the check reports `INDETERMINATE`, which is not a
pass. A standard Debian install has it and a minimal or cloud image often does
not.

Then, from a checkout of this repository at v2 or later:

```sh
git -C ~/dejima-devbox-hardener pull      # or clone it fresh
cd ~/dejima-devbox-hardener
sudo ./bin/dejima-devbox-bootstrap
```

Bootstrap is idempotent. It will re-prompt for the forge hostname and the
account, offering what you already have as the defaults, and pressing Enter at
both changes nothing. What it does that matters here is install the new
`dejima-devbox-audit`, install `dejima-devbox-upgrade`, and write
`guest_version=2` into `/etc/dejima-devbox/state`.

It also reinstalls the systemd timer, which is harmless and is how the unit
picks up any change to it.

### Check the guest half landed

```sh
sudo dejima-devbox-audit reach
```

Two `PASS` lines now, not one. The second is the IPv6 half. If it says `FAIL`,
the node work above is not in force — go back to §1 and check `ip6tables`, not
`iptables`. If it says `INDETERMINATE`, `ping` is missing.

## 3. Record the node half

```sh
sudo dejima-devbox-upgrade mark-node 2
```

This runs `dejima-devbox-audit reach` first and refuses to record the assertion
if it does not pass, so the thing being written down has been corroborated
rather than merely claimed.

## 4. Snapshot

**Take a fresh snapshot, and delete the pre-upgrade one.**

A devbox has no scheduled rollback, so nothing undoes this on a timer. What
would undo it is you, later, restoring a snapshot taken this morning — which
boots fine, passes its own v1 checks, and is missing the IPv6 rule's guest-side
counterpart while the node keeps the rule. `dejima-devbox-upgrade status` would
then report `guest_version` behind `node_version`, which is the pair disagreeing
on purpose.

Keeping the old snapshot is keeping a bootable copy of the vulnerability. If you
have a reason to keep it, name it so that its date is obvious in the list.

## What this does not change

Internet egress. Still unbounded from the VM, still deliberate, and the reason
is in `proxmox/firewall.fw.template` above `policy_out`. Rule 12 removes a second
route to the internet and a first route to your LAN; it does not narrow the
first route.
