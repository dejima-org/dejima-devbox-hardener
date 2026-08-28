---
version: 3
title: A pinhole for dejima's remote-access notifications
layers: node
downtime: none
snapshot: none
---

# v3 — a pinhole for dejima's remote-access notifications

**Only if you use dejima's remote access.** If you do not, there is nothing to
do and you can record this version and move on.

One optional rule in the console. No guest change, no new snapshot.

## Why

`dejima-notify-watch` is a systemd *user* unit on the devbox, so its push to
ntfy crosses your LAN — and a self-hosted ntfy is a private address, which rules
7 to 9 drop.

So remote access is configured, enabled, and **silently sends nothing**: no
error anywhere you are looking, and a phone that never buzzes. If you ever
configured it on a devbox and concluded it did not work, this is why.

A gap in what this project documented, not a change of position.

## If you already added it by hand

Likely, if you use the feature — it is the obvious fix once you work out what is
wrong, and it is the reason this note exists.

Check what you added against the spec rather than assuming they match:

| | Should be |
| --- | --- |
| Destination | One host — whatever `ntfy_url` resolves to. Not a subnet |
| Protocol / port | `tcp`, and the port your deployment actually serves. Do not assume 443 |
| Position | Above the DROPs, with the other pinholes |
| Direction | `out` only. Nothing needs to reach *in* for this |

If yours is wider than that, narrow it. If it matches, you are already at v3 and
only need to record it.

Three things worth re-checking, because they pass day-to-day and cost you later:

- **A rule below the DROPs does nothing**, so if pushes are arriving you got
  that right already.
- **A rule permitting the whole subnet** works identically and gives a
  compromised devbox your entire LAN, which is the thing this project exists to
  prevent. It is the shortcut most likely to have been taken at 1am.
- **A port shared with other services on the same proxy** reaches all of them,
  not just ntfy. See below — this is the one most likely to be wider than
  intended without looking wider, and the one worth fixing even if the rule is
  otherwise correct.

## The rule

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

| # | Direction | Action | Protocol | Dest. port | Source / Dest |
| --- | --- | --- | --- | --- | --- |
| 6b | out | ACCEPT | tcp | your ntfy's port | **Dest:** what `ntfy_url` resolves to |

**Check whether you need it at all first.** If `ntfy_url` resolves to a public
address, internet egress from this VM is already unbounded and the rule is
redundant. It is needed when the name resolves to a private address.

Place it with the other pinholes, **above** the DROPs. The console inserts at
the top, so it will land above them on its own — but drag it into place with the
other ACCEPTs rather than leaving it first, so the group still reads in the
order the table documents.

The destination and port must match `ntfy_url`, under `[remote-access]` in
`~/.config/dejima/config` on the devbox. Read both off the machine rather than
recalling them — the port in particular, since a reverse proxy often serves
something other than 443:

```sh
url=$(sed -n 's/^ntfy_url *= *//p' ~/.config/dejima/config)
hostport=${url#*://}; hostport=${hostport%%/*}
echo "port: ${hostport##*:}"          # prints the host again if none is set, meaning 443
getent hosts "${hostport%%:*}"        # the address the rule needs
```

## Give ntfy its own port on the proxy

Worth reading even if you already added the rule.

The rule matches an address and a port; a reverse proxy routes by hostname. So
if ntfy shares a port with other services, **the rule reaches all of them** — a
compromised devbox chooses its own `Host` header and the firewall cannot tell.
The exposure then grows silently whenever a route is added there for some
unrelated reason.

**One port per service, one rule per port** closes it. The reasoning, and the
two things to keep true on the proxy, are in `proxmox/README.md`,
["One more, if you want dejima's notifications"](../proxmox/README.md#one-more-if-you-want-dejimas-notifications).
That is also how any further service you pinhole should be added.

If ntfy is on a shared port today, moving it is a proxy-side change plus a
one-line edit here. Cheaper now than when the list has five entries and nobody
remembers which ports are shared.

**Scope the credential** to the topic dejima publishes to, if your ntfy has
access control. A token that can write more widely lets a compromised devbox
send messages that appear to come from your own infrastructure; one that can
*read* a topic carrying alerts about the devbox learns what any monitoring
noticed, which is worse.

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
