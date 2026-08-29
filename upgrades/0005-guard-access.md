---
version: 5
title: Let dejima-guard collect from this devbox
layers: node guest
downtime: window
snapshot: required
---

# v5 — let dejima-guard collect from this devbox

**Only if you run [dejima-guard](https://gitbox.branderson.io/dejima/dejima-guard).**
If you do not, there is nothing to do and you can record this version and move
on.

One optional console rule, one line in `authorized_keys`, and a snapshot.

## Why

The guard watches this devbox from a machine that is not this devbox, and it
**pulls**: it reaches in over SSH, and this box never reaches out to it. That
inversion is the whole reason a guard is worth having — a devbox that has been
taken cannot silence a watcher it cannot talk to — and it is why the work here
is one inbound pinhole and no outbound rule at all.

## 1. Node — one rule, if the guard is not already covered

**Check first.** A guard on your admin subnet is already permitted by rule 1,
and this adds nothing. This is for a guard living somewhere else, which is
where a fleet of containers usually is.

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

| # | Direction | Action | Protocol | Dest. port | Source / Dest |
| --- | --- | --- | --- | --- | --- |
| 2b | in | ACCEPT | tcp | 22 | **Source:** the guard's IP |

Place it with the other inbound rules. Ordering does not bite here the way it
does outbound — there are no inbound DROPs above it to fall behind — but keep
the group reading in the order the table documents.

**One address, not the subnet it sits on.** And **no outbound counterpart**: a
rule added for symmetry would hand back the property this design rests on.

## 2. Guest — restrict the key it comes in with

The rule above grants the chance to attempt SSH. What decides whether that is
worth anything is the key, and the key lives on a machine that is not this one
— a machine holding the evidence about this one.

[§7 of the runbook](../docs/building-a-devbox.md#7-let-the-guard-in-if-you-run-one)
has both halves: a forced command pointing at `dejima-guard-shell`, and a
sudoers rule naming the same two invocations. Together they mean a key taken
off the guard collects and does nothing else — in particular it cannot run
`drift --accept`, which would let it tell this box that whatever is on it now
is normal.

**It connects as your own account, not root.** This devbox has no root
password, which is what its runbook built, so the guard elevates through sudo
for exactly those two commands rather than logging in as root.

**Test both halves before relying on them.** The runbook has the four commands:
two that must work and two that must print `refused`. A restriction nobody
tried is a restriction nobody has.

## 3. Record it

**From the checkout, not from `/usr/local/sbin`.** Nothing in this upgrade runs
bootstrap, so the installed copy still holds the notes it was installed with —
and it will tell you there is no note for v5, which is true of the copy and not
of this repository.

```sh
cd ~/dejima-devbox-hardener
sudo ./bin/dejima-devbox-upgrade mark-node 5
```

v5 declares no check. Nothing in the guest can see a firewall rule on the node,
and whether the guard can actually connect is a question the guard answers —
run `dejima-guard check` on that machine and watch it succeed.

## 4. Snapshot

**This is the only step needing the VM stopped**, and it is the whole of this
upgrade's `downtime: window`. Everything above is live-safe.

The `authorized_keys` line is guest state, so a snapshot taken before this
restores a box the guard cannot reach. That fails loudly rather than quietly —
the guard reports the devbox unreachable — but it is a false alarm you would
then have to diagnose.

## What this does not change

Nothing about egress. The guard is reached, never called: this devbox gains no
new destination and no new reason to talk to anything.
