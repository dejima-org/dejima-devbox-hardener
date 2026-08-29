---
version: 6
title: Watch the persistence that does not need root
layers: guest
snapshot: none
downtime: none
---

# v6: watch the persistence that does not need root

Guest only, live-safe, no snapshot. **If you run dejima-guard, this needs a
fresh baseline on the guard**, which is the whole of the work.

## Why

`drift` watched `/etc`, `/usr/local/bin`, `/usr/local/sbin` and the two `.ssh`
directories. Everything in that list needs root to write. A dejima session runs
as the ordinary account, so the cheapest persistence available to it was outside
every watched path:

- a **user systemd unit** in `~/.config/systemd/user`, enabled without sudo;
- a **crontab**, which `crontab -e` writes to `/var/spool/cron/crontabs` and not
  to `/etc`;
- a **shell rc file**, run on every login;
- a **binary in `~/.local/bin`**, which is on that account's PATH and is where
  dejima installs its own CLIs.

Two more gaps were in how the state was collected rather than where:

- **Symlinks were invisible.** `find -type f` returns nothing for one, so
  replacing a watched binary with a link to another removed a `FILE` line and
  added nothing. A removal reads as tidying rather than as substitution.
- **UDP listeners were invisible.** `ss -ltn` is TCP only, so a beacon or a
  backdoor binding a datagram socket produced no line at all.

None of this widens what the guard's key may run. The audit already ran as root
under the same sudoers rule and already returned this shape of text; it was
looking in fewer places.

## 1. Guest

```sh
cd ~/dejima-devbox-hardener
git pull
sudo ./bin/dejima-devbox-bootstrap
```

Live-safe. Bootstrap installs only what is missing and does not restart Docker,
so sessions in flight are not disturbed.

**Nothing to mark.** Bootstrap records the guest version itself, because that is
the half a box can know about itself. `mark-node` exists for the other half, the
console work no guest can see, and this upgrade has none. Afterwards
`./bin/dejima-devbox-upgrade status` should read v6.

## 2. Re-accept the baseline, on the guard

**Do this or every cycle alerts.** `PORT` lines now carry the protocol, so a
baseline taken before this differs from every state taken after it on every
port, and the new paths appear as additions.

On the machine running dejima-guard:

```sh
dejima-guard accept
dejima-guard check      # should be clean
```

**Read what `accept` is about to record before you run it.** The state is
larger now and covers places nobody was watching before, so this is the first
time anything in those paths has been looked at. Take it on a box you believe is
clean; one taken later records whatever is there as normal.

If you do not run a guard, `sudo dejima-devbox-audit drift --accept` does the
same thing on the box itself, with the caveat that repository has always
carried: a baseline root can rewrite bounds an intruder who did not think to
look, and not one who did.

## What this does not change

Nothing about the firewall, the node, or what the guard is permitted to run. No
new command, no new sudoers entry, no new key. The same call returns more.
