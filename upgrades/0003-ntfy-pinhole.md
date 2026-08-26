---
version: 3
title: A pinhole for dejima's remote-access notifications
layers: node
snapshot: none
---

# v3 — a pinhole for dejima's remote-access notifications

**Only if you use dejima's remote access.** If you do not, there is nothing to
do and you can record this version and move on.

One optional rule in the console. No guest change, no new snapshot.

## Why

`dejima-notify-watch` is a systemd *user* unit on the devbox — not something in
a container — so its push to ntfy leaves the guest and crosses your LAN. A
self-hosted ntfy is a private address, which rules 7 to 9 drop.

The result is that remote access is configured, enabled, and **silently sends
nothing.** Nothing errors where you are looking. The phone never buzzes, and the
cause is in another repository's documentation. If you have configured dejima's
remote access on a devbox and concluded it did not work, this is why.

This is a gap in what this project documented, not a change of position: the
rule was always needed and was never written down.

## If you already added it by hand

Likely, if you use the feature — it is the obvious fix once you work out what is
wrong, and it is the reason this note exists.

Check what you added against the spec rather than assuming they match:

| | Should be |
| --- | --- |
| Destination | The ntfy server's address, one host — not a subnet |
| Protocol / port | `tcp` / the port your ntfy actually serves, usually `443` |
| Position | Above the DROPs, with the other pinholes |
| Direction | `out` only. Nothing needs to reach *in* for this |

If yours is wider than that — a subnet, or no port — narrow it. If it matches,
you are already at v3 and only need to record it.

Two specific things worth re-checking, because they are the ones that pass
day-to-day and cost you later:

- **A rule below the DROPs does nothing**, and pushes would still not arrive, so
  if this is working you probably got that right.
- **A rule permitting the whole subnet** works identically and gives a
  compromised devbox your entire LAN, which is the thing this project exists to
  prevent. It is the shortcut most likely to have been taken at 1am.

## The rule

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

| # | Direction | Action | Protocol | Dest. port | Source / Dest |
| --- | --- | --- | --- | --- | --- |
| 6b | out | ACCEPT | tcp | 443 | **Dest:** ntfy server IP |

Place it with the other pinholes, **above** the DROPs. The console inserts at
the top, so it will land above them on its own — but drag it into place with the
other ACCEPTs rather than leaving it first, so the group still reads in the
order the table documents.

The destination must match the host in `ntfy_url`, under `[remote-access]` in
`~/.config/dejima/config` on the devbox. Read it off the machine rather than
recalling it:

```sh
getent hosts "$(sed -n 's/^ntfy_url *= *//p' ~/.config/dejima/config | sed -E 's#^https?://##; s#/.*##')"
```

## What it costs

**The ntfy server joins this VM's blast radius.** A compromised devbox can reach
it and attack whatever it runs. One host, one port.

**It is not a new way to phone home.** Egress to the internet from this VM is
unbounded by design already, so this widens lateral reach and nothing else. The
threat model draws that distinction and it holds here.

**If your ntfy uses access control**, scope the devbox's token to the topic
dejima publishes to. A devbox that can write to other topics can send messages
that appear to come from your own infrastructure. One that can *read* a topic
carrying alerts about the devbox learns what any monitoring noticed, which is
worse than being able to write.

## Check it

There is nothing to run. `dejima-devbox-audit` verifies **containment** — that
what should be unreachable is — and a missing pinhole is the opposite shape.
The audit passes with or without this rule, which is why it declares no
`verify-node` command.

So check it the only way that works: trigger a notification and watch for it.

```sh
sudo ./bin/dejima-devbox-upgrade mark-node 3
```

The tool will tell you v3 declares no check and that this is your word for it.
That is accurate, and it is the honest state of this one.
