---
version: 2
title: The LAN boundary gains IPv6 and the CGNAT range
layers: node guest
downtime: window
snapshot: required
verify-node: dejima-devbox-audit reach
---

# v2: the LAN boundary gains IPv6 and the CGNAT range

Two rules on the hypervisor, one package and a re-run of bootstrap in the guest,
and a fresh snapshot. Budget twenty minutes, most of it waiting for the console.

**Do the node half first.** The guest half installs an audit that checks the
node half, and running it before the rules exist produces a `FAIL` that is
correct, alarming, and not about anything you did wrong.

## Why

Until you do this, **your devbox reaches its neighbours over IPv6**: on a
network with no IPv6 in it, because every Linux host answers on `fe80::`
regardless. All four v4 DROPs are in force and irrelevant, and
`dejima-devbox-audit reach` reports `PASS`, because it probes
`ip -4 route show default`.

Why the family is dropped whole rather than enumerated:
[the threat model](../docs/threat-model.md#the-lan-boundary-is-two-boundaries).

## 1. Node: two rules in the Proxmox console

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

Add these two. They are rules 11 and 12 of
[the table in the runbook](../proxmox/README.md#build-the-group-once):

| # | Direction | Action | Protocol | Dest. port | Source / Dest |
| --- | --- | --- | --- | --- | --- |
| 11 | out | DROP | - | - | **Dest:** `100.64.0.0/10` |
| 12 | out | DROP | - | - | **Dest:** `::/0` |

**Both go at the bottom, below every existing rule.** The console inserts each
new rule at the *top* of the list, so a rule left where it lands sits above your
forge and resolver pinholes. These two are DROPs; put them above the pinholes
and the devbox stops reaching its forge. Drag each one down as you add it.

Nothing else in the group changes. You are appending, not re-entering.

**If the console rejects `::/0`**, enter four rules in rule 12's position
instead: `fe80::/10`, `fc00::/7`, `ff00::/8`, `2000::/3`, which cover the same
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

## 2. Guest: the package, then bootstrap

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
sudo /usr/local/sbin/dejima-devbox-audit reach
```

The full path because these install to `/usr/local/sbin`, and `sudo` reaches
that only if your `sudoers` sets a `secure_path` including it: without one,
`sudo` inherits your own PATH, and Debian leaves every `sbin` off a non-root
PATH. `sudo printenv PATH` says which you have; bootstrap says so too if it
noticed. Elsewhere in these docs the bare name is used, and works wherever
`secure_path` is set.

Two `PASS` lines now, not one. The second is the IPv6 half. If it says `FAIL`,
the node work above is not in force: go back to §1 and check `ip6tables`, not
`iptables`. If it says `INDETERMINATE`, `ping` is missing.

## 3. Record the node half

```sh
sudo /usr/local/sbin/dejima-devbox-upgrade mark-node 2
```

This runs `dejima-devbox-audit reach` first and refuses to record the assertion
if it does not pass, so the thing being written down has been corroborated
rather than merely claimed.

## 4. Snapshot

**This is the only step here that needs the VM stopped**, and it is the whole of
this upgrade's `downtime: window`. Everything above it is live-safe: the console
rules apply without touching the guest, and the guest steps install only what is
absent. Batch it with any other work needing the box down rather than taking it
out mid-procedure.

**Take a fresh snapshot, and delete the pre-upgrade one.**

A devbox has no scheduled rollback, so nothing undoes this on a timer. What
would undo it is you, later, restoring a snapshot taken this morning, which
boots fine, passes its own v1 checks, and is missing the IPv6 rule's guest-side
counterpart while the node keeps the rule. `dejima-devbox-upgrade status` would
then report `guest_version` behind `node_version`, which is the pair disagreeing
on purpose.

Keeping the old snapshot is keeping a bootable copy of the vulnerability. If you
have a reason to keep it, name it so that its date is obvious in the list.

## 5. Confirm

```sh
cd ~/dejima-devbox-hardener
./bin/dejima-devbox-upgrade status
```

Both halves at v2, and the node check re-run to confirm the console work is
still in force.

**From the checkout, not from `$PATH`.** The installed copy at
`/usr/local/sbin` knows only the upgrades that existed when it was installed, so
it cannot tell you about a version released since: it says so rather than
reporting "up to date", but a checkout is the answer that means something.

This is also what to run in six months. `status` re-checks everything already
recorded, so a rule somebody removes later shows up here rather than in an
incident.

## What this does not change

Internet egress. Still unbounded from the VM, still deliberate, and the reason
is in `proxmox/firewall.fw.template` above `policy_out`. Rule 12 removes a second
route to the internet and a first route to your LAN; it does not narrow the
first route.
