---
version: 7
title: Stop reporting ephemeral sockets as listeners
layers: guest
snapshot: none
downtime: none
---

# v7: stop reporting ephemeral sockets as listeners

Guest only, live-safe. **Fixes an alert that fires every cycle on a box where
nothing is happening**, introduced by v6.

## Why

v6 added UDP to the listening-socket collection, which was a real gap: a beacon
binding a datagram socket produced no line at all.

`ss -l` with `-u` also reports UDP sockets in `UNCONN`, and that is what a
client socket looks like. A resolver doing a lookup holds one on a random high
port for as long as the query takes, and TCP has the same shape for anything
that binds before connecting. So a box doing nothing produced a new `PORT` line
every cycle and lost the one from the cycle before.

To a watcher that is a listener appearing and disappearing. On dejima-guard it
lands as `new listener or unit` at max priority, roughly every half hour, and
`accept` does not help because the next sample differs again. The heartbeat
flaps with it: it fires only on a clean cycle, so the alerting ones send nothing
and the dead-man's switch reports the guard down and up in turn.

Nothing was wrong with the watched machine on any of those cycles.

## What changed

Ports inside the kernel's ephemeral range are not recorded. The range is read
from `/proc/sys/net/ipv4/ip_local_port_range` rather than written down, since it
is tunable and a wrong constant would either keep the flapping or hide real
services.

**What this gives up:** a listener the kernel would also hand out as an
ephemeral port is no longer recorded. That is a real loss and it is the better
trade, because the alternative is an alert every cycle, and an alert that fires
constantly is one nobody reads.

## 1. Guest

```sh
cd ~/dejima-devbox-hardener
git pull
sudo ./bin/dejima-devbox-bootstrap
```

Live-safe, and bootstrap records the version itself.

## 2. Re-accept the baseline

The ephemeral lines are gone from the state, so a baseline taken under v6
differs from every state taken after this.

On the machine running dejima-guard:

```sh
docker compose exec dejima-guard dejima-guard accept
docker compose exec dejima-guard dejima-guard check
```

Without a container, drop the prefix. If you do not run a guard,
`sudo dejima-devbox-audit drift --accept` does the same on the box itself.
