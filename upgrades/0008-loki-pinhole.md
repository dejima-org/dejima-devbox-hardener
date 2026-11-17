---
version: 8
title: A pinhole for dejima's log shipping to Loki
layers: node
downtime: none
snapshot: none
---

# v8: a pinhole for dejima's log shipping to Loki

**Only if you set `[logging] loki_url`.** If you do not, there is nothing to do
and you can record this version and move on.

One optional rule in the console. No guest change, no new snapshot.

## Why

A self-hosted Loki is a private address, which rules 7 to 9 drop. So the logs
stop arriving and nothing says why: dejima pushes with `curl` and discards the
result, because a logging endpoint that is down must not be able to fail a
launch.

The symptom is distinctive once you know it. **All three streams go silent
together** - `dejima-dns`, `dejima-net` and, if you opted into it,
`dejima-conversation` - while the session itself works perfectly. A Loki that
has stopped receiving looks exactly like a devbox nobody ran anything on.

This was a gap in what the project documented rather than a change of position.
The equivalent rule for notifications has been here since v3; this one was
never written down, so the firewall built by following `proxmox/README.md` drops
the logs it never mentioned.

## If you already added it by hand

Likely, if you use the feature. Check what you added rather than assuming it
matches:

| | Should be |
| --- | --- |
| Destination | One host: whatever `loki_url` resolves to. Not a subnet |
| Protocol / port | `tcp`, and the port your deployment serves. Loki's own default is 3100; behind a proxy it is whatever that proxy listens on |
| Position | Above the DROPs, with the other pinholes |
| Direction | `out` only. Nothing needs to reach *in* for this |

The same three things are worth re-checking as for ntfy, for the same reasons:
a rule below the DROPs does nothing, a rule naming the whole subnet gives a
compromised devbox your entire LAN, and a port shared with other services on
the same proxy reaches all of them. `upgrades/0003-ntfy-pinhole.md` has the
reasoning and `proxmox/README.md` has the nginx.

## The rule

**Datacenter → Firewall → Security Group → `dejima-devbox-hardener`.**

| # | Direction | Action | Protocol | Dest. port | Source / Dest |
| --- | --- | --- | --- | --- | --- |
| 6c | out | ACCEPT | tcp | your Loki's port | **Dest:** what `loki_url` resolves to |

**Check whether you need it at all first.** If `loki_url` resolves to a public
address, internet egress from this VM is already unbounded and the rule is
redundant. It is needed when the name resolves to a private address, which a
self-hosted Loki usually does.

Place it with the other pinholes, **above** the DROPs. The console inserts at
the top, so it lands above them on its own; drag it into place with the other
ACCEPTs so the group still reads in the order the table documents.

Read the destination and port off the machine rather than recalling them:

```sh
url=$(sed -n 's/^loki_url *= *//p' ~/.config/dejima/config)
hostport=${url#*://}; hostport=${hostport%%/*}
host=${hostport%%:*}
port=${hostport##*:}
# No ":port" in the URL leaves port and host the same string, and the scheme
# decides it instead.
if [ "$port" = "$host" ]; then
    port=80
    [ "${url#https://}" = "$url" ] || port=443
fi
# The URL echoed first: an unset key would otherwise print a confident
# "port: 80" for a host that is the empty string.
printf 'url:  %s\nhost: %s\nport: %s\n' "$url" "$host" "$port"
getent hosts "$host"          # the address the rule needs
```

## Two senders, one rule

Worth knowing, because it is not the shape the notification pinhole has.

`dejima-conversation` ships from the VM, like notifications do: a host-side
reader, deliberately outside the container so a session cannot silence its own
oversight log. `dejima-dns` and `dejima-net` ship from **inside** the
container, because those files only exist there.

One hypervisor rule covers both - the container's packets leave through the
VM's tap device like everything else - so there is nothing extra to add for the
second sender. What differs is what else bounds it: dejima's own egress
allowlist permits the Loki host inside the container automatically, and clamps
it to that host and port when the address is the VM's own. The notification
pinhole has no such second layer, which is why v3 says the width of its rule is
the entire answer and this one does not.

That cuts both ways. The in-container allowlist is a dejima control, so it is
configured per launch and is not a property of this VM. The hypervisor rule is
what this project is responsible for, and it is the one that was missing.

## Scope the credential, if your Loki has one

A token that can **write** more widely than dejima's own streams lets a
compromised devbox forge log lines that appear to come from your other
machines. One that can **read** lets it find out what your monitoring noticed
about it, which is worse. Grafana's own access to the same Loki is a separate
credential and does not need the write scope at all.

## Check it

There is nothing to run. `dejima-devbox-audit` verifies **containment** - that
what should be unreachable is - and a missing pinhole is the opposite shape, so
the audit passes with or without this rule. That is why this version declares
no `verify-node` command.

Check it the way the logs themselves tell you. Run anything in a session, then
query the stream that ships from inside the container and the one that ships
from the VM:

```logql
{job="dejima-dns"}
{job="dejima-conversation"}
```

The first proves the container's push got out. The second proves the host's did,
and only if you have `[logging] conversation = on`.

```sh
sudo ./bin/dejima-devbox-upgrade mark-node 8
```

The tool will tell you v8 declares no check and that this is your word for it.
That is accurate, and it is the honest state of this one.
