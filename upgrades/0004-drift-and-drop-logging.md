---
version: 4
title: The audit reports what changed, and the node logs what it dropped
layers: node guest
snapshot: required
verify-node: dejima-devbox-audit drift
---

# v4 — the audit reports what changed, and the node logs what it dropped

Six rules get a log level in the console. The guest gets a new audit
subcommand and a baseline. Twenty minutes, most of it deciding what your normal
looks like.

**This is not intrusion detection yet**, and the note says so where you can see
it rather than in a design document. See "What this does and does not buy" at
the end before relying on any of it.

## Why

A devbox has no upper bound on how long a foothold lasts. Its sister project is
rebuilt from a snapshot on a schedule, so anything that gets in has until the
next rollback; a devbox holds uncommitted work and is never rebuilt, so nothing
reclaims it and nothing is looking.

Two cheap things change that a little. The node can log the packets it drops,
and the guest can notice that something on it is different from yesterday.

## 1. Node — log the DROPs

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

Edit rules **7 to 12** — the six DROPs — and set **Log level: `info`**. Leave
every other rule, and both policies, at `nolog`.

Nothing else changes. No rule is added or removed.

**Why only those six.** A packet matching a DROP is this VM trying to reach
your network, which on a working devbox is close to never: the forge and the
resolver have pinholes above, and nothing else it does legitimately goes to a
private address. The log is therefore quiet by construction, and a burst in it
is the loudest signal a compromised devbox produces.

Logging the policies instead would be useless. `policy_out` is ACCEPT, so it
would record the machine's entire internet traffic; `policy_in` drops broadcast
chatter all day.

**Where it lands.** `/var/log/pve-firewall.log` on the node, and the
**Firewall → Log** panel for the VM. That is outside the guest, which is the
point — every other observation this project makes runs inside the VM, where
root can stop it.

**Expect noise for a week.** mDNS, SSDP and NetBIOS will all appear on a
perfectly healthy box. The signal is not that a drop happened; it is a
destination this VM has never tried before. Read it for a while before deciding
what normal looks like, and do not start alerting on it until you have.

## 2. Guest — update and take a baseline

From a checkout at v4 or later:

```sh
git -C ~/dejima-devbox-hardener pull
cd ~/dejima-devbox-hardener
sudo ./bin/dejima-devbox-bootstrap
```

Then, **on a box you believe is in a known state**:

```sh
sudo dejima-devbox-audit drift --accept
```

That records a hash of every file under `/etc`, `/usr/local/bin`,
`/usr/local/sbin` and the `.ssh` directories, plus the enabled systemd units and
the listening ports. It writes to `/var/lib/dejima-devbox/baseline`.

**Take it before you believe the box is dirty, not after.** A baseline records
whatever is there when it runs, so one taken on a compromised machine records
the compromise as normal and reports clean forever.

From then on:

```sh
sudo dejima-devbox-audit drift
```

`CLEAN`, `DRIFT` with the changes listed, or `INDETERMINATE` if it could not
compare — no baseline, or paths it could not read. `INDETERMINATE` is not a
pass, for the same reason it is not one in `reach`.

**Run it under `sudo`.** Without the privilege to read every watched path the
state comes back partial, and a partial state diffs against a full baseline as
a list of *removals* — which reads as an intruder deleting things. The command
refuses to compare rather than report that, which is why it says
`INDETERMINATE` instead of failing usefully-looking.

### Living with it

An ordinary `apt upgrade` moves a lot of lines. Read them, and if they are
yours:

```sh
sudo dejima-devbox-audit drift --accept
```

There is no finer-grained acknowledgement, and that is a real limitation rather
than an oversight: accepting individual findings needs somewhere to record which
ones, which is the collector this design has not built yet.

`dejima-devbox-audit` with no argument now runs all three — radius, drift,
reach — and exits non-zero if **any** of them is unhappy. The timer still runs
`reach` alone.

## 3. Snapshot

`snapshot: required`, and for an unusual reason: the baseline is guest state, so
a snapshot taken before this upgrade restores a box with no baseline, and one
taken before an `--accept` restores the older baseline. Neither is dangerous —
both fail towards `INDETERMINATE` or a noisy `DRIFT` rather than towards a false
clean — but both are confusing if you have forgotten.

## What this does and does not buy

**It does not detect an intruder who went looking.** The baseline is a file on
this machine, and root here can rewrite it as easily as read it. Root here is
the case being looked for.

What it catches is a payload that did not think to look — which is most of them,
because the adversary in this threat model is a prompt injection or a dependency
that did not choose this devbox and has no idea what is on it.

**Nothing alerts you.** Both halves write to a log nobody reads: the node's
firewall log, and the audit's own output in the journal. A signal you never see
is not detection, and calling it that would be the same mistake as reporting a
timeout as a pass.

The design that closes both gaps is a collector on a machine that is not this
one, holding the baseline and pushing an alert when something changes or when
this box stops answering. That is the next step and it is not built. Until it
is, this is a thing you run by hand and read yourself.
