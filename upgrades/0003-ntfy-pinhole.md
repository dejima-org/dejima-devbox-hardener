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

This is the part worth reading even if you already added the rule.

The rule matches an address and a port and nothing else. Proxmox cannot filter
by hostname; a reverse proxy routes *by* hostname. So if ntfy shares a port with
other services on that proxy, **the rule reaches all of them** — a compromised
devbox chooses its own `Host` header and the firewall cannot tell. The blast
radius is then whatever is behind that port, and it grows silently whenever a
route is added there for some unrelated reason.

**One port per service, one rule per port** closes that. The port is enforced on
the node, where the guest cannot reach it, so the rule grants exactly ntfy and
the rule list reads as what it claims to be. `proxmox/README.md`,
["Reaching a service behind a reverse proxy"](../proxmox/README.md#reaching-a-service-behind-a-reverse-proxy),
is the general form, and it is how any further service you pinhole should be
added.

If you already gave ntfy a shared port, moving it is a proxy-side change and a
one-line edit here. Worth doing now rather than at the point where the list has
five entries and nobody remembers which ports are shared.

Two things to keep true on the proxy, both in dejima's
`docs/nginx-dejima.conf.example`: a reject `default_server` on each listen, or
`server_name` isolates nothing; and `$http_host` rather than `$host` on any port
other than 443, or a service comparing `Origin` against `Host` refuses every
request.

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
