# Threat model

What this defends, what it does not, and which options were rejected on
purpose. The last section matters most: it exists so a decision can be
overturned on new information rather than re-argued from nothing.

## Ranked by what is actually likely

1. **Lateral movement onto the operator's LAN.** A session runs code the
   operator did not write: dependencies, build scripts, fetched content. None
   of that needs an exploit to attempt a connection to another host on the
   network.
2. **Cross-project context poisoning.** A session writes another project's
   agent memory or transcripts, so a later session in that project reads
   planted text as established background.
3. **Root on the devbox VM.** Reachable by container escape or by any other
   local privilege escalation.

The ordering is the point. The controls in this repository are aimed at 1,
because 1 is the one a devbox is exposed to during ordinary use rather than
under attack.

## Why container escape is deprioritised

Escapes are real and they recur: runc `CVE-2019-5736` and `CVE-2024-21626`,
containerd `CVE-2020-15257`, cgroups v1 `release_agent` `CVE-2022-0492`, and
kernel privilege escalations reachable from inside a container such as Dirty
Pipe and the `nf_tables` family. This is not a claim that escape is impossible.

Every one of those requires an unpatched host or a working zero-day, which
describes a targeted attacker. The realistic adversary here is a prompt
injection in fetched content or a malicious dependency in something the agent
installs, and neither arrives with an exploit. Both use permissions that were
already granted.

The decisive point is that **an escape would be a downgrade.** A session already
holds a forge credential, which is code access to every repository that
credential can see, plus whatever the container mounts. Escaping into an
unprivileged account on the devbox grants less than the session already has.
Nobody takes that trade.

So the proportionate control is keeping the kernel and the container runtime
patched, which costs no usability at all. `dejima-devbox-audit` reports the
running kernel against the newest installed one for that reason: a fix that is
installed but not booted is not a fix.

Architectural separation between escape and root is not pursued. See
[Rejected, with reasons](#rejected-with-reasons).

## What dejima already handles

`docker/init-firewall.sh` sets the container's `OUTPUT` policy to `DROP` and
allowlists explicitly. On the LAN specifically it permits the Docker host's own
address and not the host's subnet, with the comment that other machines on the
same LAN have no reason to be reachable from the container.

Container-level lateral movement is therefore already closed, and this project
does not duplicate or second-guess it.

What dejima cannot bound is the devbox VM's own network access, because dejima
runs inside that VM. That gap is this project's entire subject.

## Blast radius by layer

| Layer | Reached by | Radius |
| --- | --- | --- |
| Container | normal operation | allowlisted egress, the forge credential's scope, mounted paths |
| Devbox VM, unprivileged | container escape | everything on the VM the account can read, plus the VM's network position |
| Devbox VM, root | escape plus local escalation, or misconfiguration | the whole VM and its network position |
| LAN | any of the above, if unbounded | every host the VM can route to |
| Hypervisor | out of scope | named for completeness |

This repository's contribution is to make the last two rows small, and to make
every row verifiable rather than asserted. `dejima-devbox-audit` is the
verification: rows four and five by behaviour, rows two and three by inventory.

## Rejected, with reasons

Recorded so they are not re-proposed without new information. Each of these is
a defensible idea that lost to a specific argument, not an oversight.

**Rootless Docker or Podman, taking the launching account out of the `docker`
group.** Buys separation between a container escape and root on the VM. Rejected
because escape is the least likely path and the account already holds more than
the escape would grant, so the separation protects the wrong thing. There is
also a live feasibility risk: dejima builds its own `iptables` and `ipset`
firewall inside the container and needs `NET_ADMIN`, which may not survive a
rootless runtime. Revisit if the threat model shifts toward a targeted attacker,
or if dejima stops needing `NET_ADMIN`.

**Per-project or per-session Unix users.** Buys separation between projects.
Rejected because cross-project code access already exists through the forge
credential, so this addresses the smaller half of the concern while imposing
per-user image stores, per-user daemons and ownership churn. Per-session users
additionally fail quietly, through stale UIDs on git objects and caches. The
half worth closing is agent memory, and that is dejima#104 rather than anything
a Unix account boundary would fix.

**Scheduled rollback.** Rejected because it destroys uncommitted work, which is
the thing a devbox exists to hold. This is the largest single difference from
the sister project, whose entire containment story is that a runner is rebuilt
nightly. Snapshots here stay manual.

**Detection and forensics tooling beyond the audit.** Out of scope. The audit
reports state, not history.

**Changing how dejima runs.** Out of scope in both directions. Container-level
controls belong in dejima, and the one change this project would want there is
filed as dejima#104 rather than worked around here.

## What this repository does not claim

It does not prevent root on the devbox. Nothing here tries to.

What it does is bound what a compromised VM reaches, and state that bound in a
form you can check. Everything else follows from taking that limit seriously
rather than dressing it up.
