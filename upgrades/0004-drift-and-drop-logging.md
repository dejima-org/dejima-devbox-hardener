---
version: 4
title: The audit reports what changed, and the node logs what it dropped
layers: node guest
downtime: window
snapshot: required
---

# v4: the audit reports what changed, and the node logs what it dropped

Six rules get a log level in the console. The guest gets a new audit subcommand
and a baseline. Twenty minutes.

**This is not intrusion detection**, and nothing alerts you. Read
[what it does and does not buy](#what-this-does-and-does-not-buy) before
relying on any of it.

## Why

A devbox has no upper bound on how long a foothold lasts: nothing rebuilds it
and nothing is looking. Two cheap things change that a little: the node can log
what it drops, and the guest can notice that something is different from
yesterday.

## 1. Node: log the DROPs

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

Edit rules **7 to 12**: the six DROPs, and set **Log level: `info`**. Leave
every other rule, and both policies, at `nolog`.

Nothing else changes. No rule is added or removed.

**Why only those six.** A packet matching a DROP is this VM reaching for your
network, which on a working devbox is close to never. The log is quiet by
construction, and a burst in it is the loudest signal a compromised devbox
makes. The policies would be useless: `policy_out` is ACCEPT and would record
all this machine's internet traffic.

**Where it lands.** `/var/log/pve-firewall.log`, and the **Firewall → Log**
panel. Outside the guest, which is the point, since every other observation
here runs inside the VM where root can stop it.

**Expect a week of noise.** mDNS, SSDP and NetBIOS all appear on a healthy box.
The signal is not that a drop happened but that a destination appeared this VM
has never tried. Do not alert on it before you know what normal looks like.

## 2. Guest: update and take a baseline

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

Hashes `/etc`, `/usr/local/{bin,sbin}` and the `.ssh` directories, plus enabled
units and listening ports, into `/var/lib/dejima-devbox/baseline`.

**Take it before you believe the box is dirty.** A baseline records whatever is
there, so one taken on a compromised machine records the compromise as normal
and reports clean forever.

From then on:

```sh
sudo dejima-devbox-audit drift
```

`CLEAN`, `DRIFT` with the changes listed, or `INDETERMINATE` if it could not
compare: no baseline, or paths it could not read. `INDETERMINATE` is not a
pass, for the same reason it is not one in `reach`.

**Run it under `sudo`.** Without privilege to read every watched path the state
is partial, and a partial state diffs as a list of *removals*, which reads as
an intruder deleting things. It refuses to compare rather than report that.

### Living with it

An ordinary `apt upgrade` moves a lot of lines. Read them, and if they are
yours:

```sh
sudo dejima-devbox-audit drift --accept
```

Acknowledgement is all-or-nothing. Accepting individual findings needs
somewhere to record which ones, which is the collector, which is not built.

`dejima-devbox-audit` with no argument now runs all three and exits non-zero if
any is unhappy. The timer still runs `reach` alone.

## 3. Record the node half

```sh
sudo dejima-devbox-upgrade mark-node 4
```

**It will tell you this one is your word for it, and that is correct.** v4
declares no check, because nothing in the guest can see a log level on the
hypervisor: `drift` and `reach` both verify things about *this* machine, and
whether the node writes a line when it drops a packet is not one of them.

Verify it on the node instead, once, by making the VM try something and looking:

```sh
sudo tail -f /var/log/pve-firewall.log
```

## 4. Snapshot

**This is the only step here that needs the VM stopped**, and it is the whole of
this upgrade's `downtime: window`. Everything above it is live-safe: the console
rules apply without touching the guest, and the guest steps install only what is
absent. Batch it with any other work needing the box down rather than taking it
out mid-procedure.

The baseline is guest state, so an older snapshot restores an older baseline or
none. Neither is dangerous: both fail towards `INDETERMINATE` or a noisy
`DRIFT`, never a false clean, but both are confusing if you have forgotten.

## What this does and does not buy

**It does not detect an intruder who went looking.** The baseline is a file on
this machine and root here can rewrite it, and root here is the case being
looked for. It catches a payload that did not think to look, which is most of
them, since the adversary here did not choose this devbox.

**Nothing alerts you.** Both halves write to a log nobody reads. A signal you
never see is not detection, and calling it that would be the same mistake as
reporting a timeout as a pass.

What closes both gaps is a collector on another machine, holding the baseline
and pushing an alert when something changes or when this box goes quiet. Not
built. Until it is, this is something you run and read yourself.
