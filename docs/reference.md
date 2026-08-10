# Reference

Detail that would clutter the README.

## The three verdicts

`dejima-devbox-audit reach` probes the default gateway on 443, 80 and 22, and
reports one of three things.

| Verdict | Means | Exit |
| --- | --- | --- |
| `PASS` | Every probe timed out, **and** a positive control succeeded | 0 |
| `FAIL` | Something answered: a handshake, or a refusal | 1 |
| `INDETERMINATE` | Every probe timed out and the positive controls also failed | 1 |

**Why three and not two.** A timeout means "no answer came back", which is the
firewall working or the network being broken. Reading it as a pass is a false
negative, and false negatives are the wrong direction here: the operator stops
looking. So silence alone is never enough.

**Why a refusal is a failure.** A closed port still proves the packet reached a
live host and something sent an answer back. Silently dropped is the only state
that counts as contained.

**Why not 53.** The resolver exception may legitimately permit it, so a rule
working exactly as designed would read as a failure.

**Why the gateway.** Its address is already in the routing table, so naming it
writes down nothing an attacker on this box could not read anyway. It is
guaranteed to be alive, which an arbitrary address is not. And it sits inside
the ranges the firewall drops, so with the rules applied it must be unreachable
as a destination while traffic *through* it is untouched.

**The strongest case is free** when your resolver is your gateway, which is
common on home networks: one host answers on 53 and times out on 443, and no
routing failure can produce that.

**A known limit.** `bash`'s `/dev/tcp` cannot distinguish `ECONNREFUSED` from
`EHOSTUNREACH`, so a rule that REJECTs rather than DROPs looks like a live host
refusing and produces `FAIL`. That is the safe direction to be wrong in, and it
is why the template specifies DROP.

## The positive controls

Either one is sufficient:

- the forge's name resolves, which exercises the resolver exception;
- the forge answers on 443, which exercises layer 4 and the forge exception.

Requiring both would turn an unrelated outage into a report that gets ignored.

## The three addressing modes

| Mode | Boundary cost | Maintenance |
| --- | --- | --- |
| Static in the guest | None. Four DROPs plus the named exceptions, and no DHCP rules | The address is asserted in two places |
| Reserved at the router | Needs both halves of the DHCP pair | One source of truth |
| Plain DHCP | Same DHCP pair | None, but the address moves |

Static is the recommended default here, on the strength of being the only mode
that needs no DHCP rules at all.

Plain DHCP is more workable here than in the sister project, because the inbound
rules are scoped to client subnets rather than to this VM's own address, so a
changed lease breaks nothing in the rule set.

### What the audit reports about addressing

`dejima-devbox-audit radius` names the mode and, on DHCP, checks the lease.

Static is decided before any lease file is consulted, deliberately: a host
pinned by `dejima-devbox-static-ip` keeps the leases from whatever it was doing
before, and letting those decide would tell every pinned host it needs rules it
does not need. A setup matching neither is reported as `unknown` rather than
assumed to be the friendlier answer.

**The lease check exists for the worst failure in this design.** A DHCP guest
behind these rules renews through a path the firewall may be dropping. Nothing
breaks at boot, because the first lease was obtained before the rules mattered.
The VM stops renewing and falls off the network up to a full lease time later,
looking nothing like a firewall rule.

It is detected without keeping any state between runs. The obvious design
records the expiry each run and watches whether it advances, which means this
program starts writing files. It does not need to: `dhclient` rewrites the lease
file on every successful renewal, so the file's own mtime against the renewal
time it records answers the question in one pass. Past T1 with an mtime older
than T1 means `dhclient` asked and got nothing back, which is exactly the shape
of a dropped reply, and it is visible hours before the lease expires.

## Configuration

`/etc/dejima-devbox/config`, one key:

```
forge_host=forge.example.invalid
```

That value must match the destination of the forge rules on the hypervisor.
They are entered in two places and are silent when they disagree: the audit
reports `INDETERMINATE`, which is correct and unhelpful.

Prefer a name over an address. Both work, but `getent hosts` on an address is a
reverse lookup, and a forge without a PTR record fails it, so the resolution
control quietly stops contributing.

**There is no list of what this VM must not reach, and there should never be
one.** Such a list is a map of valuable targets kept on the machine this project
assumes will be owned, describing topology not otherwise obtainable from here
without loud scanning.
