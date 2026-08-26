# Threat model

**And none of it has been reviewed by anyone else.** This is early development:
the reasoning here is one person's, the tests assert what that person thought to
check, and no outside audit or adversarial testing has happened. Read what
follows as claims awaiting scrutiny rather than claims that have survived it.
See [SECURITY.md](../SECURITY.md).

What this defends, what it does not, and which options were rejected on
purpose. The last section matters most: it exists so a decision can be
overturned on new information rather than re-argued from nothing.

## What this tool assumes

**One person's work per devbox.** This is not optional. It is a requirement for
this tool's threat model: a machine holding more than one person's work is out
of spec here, and the reasoning in this document does not hold for it.

The reason is that the blast radius is stated in terms of what is on the box. A
session already has the project it was launched for, so on a single-user devbox
the gap between "what the session has" and "what the machine holds" is small,
and that gap is what every rejected control below would have protected. Put two
people's work on one devbox and the gap is no longer small, several decisions
here become wrong, and nothing in this repository will notice.

If you need separation between people, the supported answer is a devbox each.

## Ranked by what is actually likely

1. **Lateral movement onto the operator's LAN.** A session runs code the
   operator did not write: dependencies, build scripts, fetched content. None
   of that needs an exploit to attempt a connection to another host on the
   network.
2. **Cross-project context poisoning.** A session writes another project's
   agent memory or transcripts, so a later session in that project reads
   planted text as established background. Handled in dejima, which scopes the
   mounts that would carry it; see below.
3. **Root on the devbox VM.** Reachable by container escape or by any other
   local privilege escalation.

The ordering is the point. The controls in this repository are aimed at 1,
because 1 is the one a devbox is exposed to during ordinary use rather than
under attack, and because 2 is not this repository's to fix.

## Why container escape is deprioritised

Escapes are real and they recur: runc `CVE-2019-5736` and `CVE-2024-21626`,
containerd `CVE-2020-15257`, cgroups v1 `release_agent` `CVE-2022-0492`, and
kernel privilege escalations reachable from inside a container such as Dirty
Pipe and the `nf_tables` family. This is not a claim that escape is impossible.

Every one of those requires an unpatched host or a working zero-day.

**The adversary this model is about is not a person.** It is a prompt injection
sitting in content the agent fetches - a web page, an issue body, a README, a
dependency's own documentation - or code that runs during an ordinary build,
such as an npm `postinstall` or a transitive dependency updated yesterday.

What they share is that **neither was written for this machine.** A prompt
injection waits for whichever agent reads it; a malicious package targets
everyone who installs it. Nobody chose this devbox.

**That says nothing about how capable the payload is, and it would be wrong to
assume it is simple.** Real supply-chain malware fingerprints its environment,
pulls a second stage, beacons to a server, and can hand a live session to a
person. A prompt injection needs to carry none of that itself: the agent
reading it is the adaptive component, and instructing an agent is the cheapest
way to get behaviour that responds to what it finds.

So this model does not rest on the attacker being unsophisticated, and nothing
below should be read as assuming it.

**Nor does it claim to stop any of that.** Staging, beaconing and handing a
session to a person all need egress to the internet, and the node firewall does
not bound egress to the internet. It bounds egress to *your network*:
`policy_out` is ACCEPT with the private ranges dropped, which is a deliberate
choice argued in full in `proxmox/firewall.fw.template`. A process on this VM
reaches any public address it likes.

Egress to the internet is bounded one layer in, by dejima's own allowlist inside
the container, and **an escape is precisely what leaves that behind.** Out on
the VM there is no allowlist, so a payload that could previously only talk to
the handful of domains a session was granted can now fetch what it wants and
report to whom it wants.

What the node firewall buys against a capable adversary is narrower and still
worth having: the second stage cannot be pulled from your NAS, and the person
handed a foothold cannot use it to reach the rest of your network. It bounds
where the compromise can *spread*, not whether it can phone home.

Being undirected changes what is likely, not what is possible. It makes an
unpatched host the more probable route than a zero-day, which is why patching
is kept and why it is cheap. It is not a reason to treat the payload as
harmless if it gets in.

**An escape grants more than the container had.** Root on the VM is strictly
more capability than a process inside a container with a trimmed capability set.

Some of what it reaches is already in the container: the forge credential, and
the working tree of the project the session was launched for. Some is not.
Every other project on the box becomes readable, and uncommitted work in those
is the part that exists nowhere else - the forge has the rest.

**And one thing is neither, and it is the sharpest consequence of an escape
onto a devbox.**

dejima keeps the model API credential out of the container deliberately.
`~/.claude/.credentials.json` is never mounted; a host-side proxy holds the real
token and the container gets a placeholder. The effect is that a compromised
session can use the API while it runs and cannot walk away with a durable
credential.

That file is on the devbox. An escape onto the devbox is exactly the step that
converts "can use the API while this session lasts" into "holds the token, and
can keep using it afterwards from anywhere". It is the one credential §7 of the
runbook cannot tell you to move off the machine, because the proxy has to read
it there.

**Root on this VM is already a row in the blast radius table below.** It is the
case the model is drawn around, not one it omits. The hypervisor firewall
bounds that row, and bounds it identically however root was reached - by a
container escape, by a local privilege escalation, or by an operator mistyping
something at a console.

So separation inside the guest is not pursued. A rootless runtime changes how
hard root is to reach without changing anything about what root can reach once
there, and what root can reach is already bounded and already written down.

What is left worth doing is keeping the kernel and the container runtime
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

**Cross-project context poisoning is closed there too.** `bin/dejima` scopes
both mounts that would carry it: `~/.claude/projects` one slug at a time, the
launching workspace's own plus its live worktree children, and
`~/.claude/file-history` one session at a time, filtered to the sessions
belonging to that workspace.

Some sibling directories - `tasks`, `plans`, `sessions`, `backups` - are mounted
host-wide. They are keyed by session identifier rather than by project and are
not loaded into a session's context at startup, so they do not carry the
property that makes the other two worth scoping. Worth re-checking if that
changes.

What dejima cannot bound is the devbox VM's own network access, because dejima
runs inside that VM. That gap is this project's entire subject.

## The LAN boundary is two boundaries

The control aimed at lateral movement is a list of ranges dropped on the
hypervisor, and a list bounds only what it names. So both address families are
named, separately, because a rule naming an IPv4 range matches no IPv6 traffic
at all.

The second family needs covering even on a network that routes no IPv6. Every
Linux host brings up an `fe80::` address on every interface whether or not
anything routes v6, and a daemon bound to `::` answers on it. With every private
IPv4 range dropped and nothing said about v6, the machine beside this one is
still one `ssh fe80::...%eth0` away, over a path that does not appear in
`ip -4 route`, does not involve the router, and is invisible to anyone checking
that the v4 rules are right.

**IPv6 has no RFC 1918.** The v4 list works because three ranges cover every
private network there is. A v6 network is numbered out of a globally routable
prefix delegated by an ISP, so no equivalent list can be written down here:
`fc00::/7` catches unique-local addresses most networks do not use and misses
the prefix a neighbour is actually on. The set cannot be enumerated, so the
family is dropped whole, on the node, as rule 12 of the security group.

This costs nothing that is claimed elsewhere. Internet egress stays unbounded
and stays over IPv4, for the reasons argued in `proxmox/firewall.fw.template`.
What rule 12 removes is a second route to the internet and a first route to the
LAN.

The audit verifies it the way it verifies the rest, by behaviour: it asks
`ff02::1` who is on the link and counts the replies that are not its own. A v4
timeout is ambiguous, because a working firewall and a broken network look alike
from in here. A v6 silence is not, because both of its causes - dropped at the
node, or never configured at all - are the outcome wanted, and no service a
devbox needs lives on that family for the silence to be hiding one. So that half
needs no positive control. What it does still report separately is a probe that
could not run at all, which is not containment and is not allowed to read as it.

## Blast radius by layer

| Layer | Reached by | Radius |
| --- | --- | --- |
| Container | normal operation | the forge credential's scope, mounted paths, and egress to allowlisted domains only |
| Devbox VM, unprivileged | container escape | everything on the VM the account can read, and **unrestricted egress to the public internet** |
| Devbox VM, root | escape plus local escalation, or misconfiguration | the whole VM, the same unrestricted internet egress, and **the model API credential** |
| LAN | any of the above, if unbounded | every host the VM can route to, in either address family |
| Hypervisor | out of scope | named for completeness |

The jump from row one to row two is the one to read twice, and it is not only
about privilege. Allowlisted egress becomes unrestricted egress, because the
allowlist lives in the container. **This repository does not narrow that back
down**, and nothing on the VM does: exfiltration and command-and-control are
out of scope here, deliberately, and the argument for permitting outbound
internet traffic is in `proxmox/firewall.fw.template`.

What this repository contributes is the last two rows: what the compromise can
spread to, rather than whether it can talk. And it makes every row verifiable
rather than asserted. `dejima-devbox-audit` is the
verification: rows four and five by behaviour, rows two and three by inventory.

## Not bounded

Everything above is organised by control, which leaves the reader to assemble
the negative space themselves. Most will not. So, in one place, what a devbox
running this is *not* protected from. Each line has its argument somewhere above
or below; this list exists so that nobody has to go looking to find out whether
there is one.

- **Exfiltration, and command-and-control.** Egress to the internet is
  unbounded from the VM, deliberately. A payload out on the VM fetches what it
  likes and reports to whom it likes. dejima's allowlist bounds this inside the
  container, and an escape is precisely what leaves it behind.
- **Container escape.** Deprioritised on purpose. Nothing here separates an
  escape from root on the VM, and the rejected alternatives are below.
- **Root on the devbox.** Not prevented. Bounded, stated, and checkable, which
  is a different claim.
- **The model API credential.** On this box, and it cannot be moved off,
  because the proxy that holds it has to read it here. An escape converts "can
  use the API while this session lasts" into "holds the token".
- **The two LAN exceptions.** The forge and the resolver are reachable from
  this VM on the ports listed, by anything on it. "No LAN access" is not
  literally true and never was.
- **Inbound exposure.** The node's inbound list is yours to keep short and
  nothing here checks it. It can only be checked from outside the VM, and this
  tool does not go looking for things to connect to.
- **Other people's work.** Out of spec. One person's work per devbox is a
  condition, not an observation.
- **History.** The audit reports state. There is no detection and no forensics
  here, so it will tell you a rule is missing and never that it once was.
- **The hypervisor itself.** Out of scope, and it is the layer everything above
  is standing on.

## Rejected, with reasons

Recorded so they are not re-proposed without new information. Each of these is
a defensible idea that lost to a specific argument, not an oversight.

**Rootless Docker or Podman, taking the launching account out of the `docker`
group.** Buys separation between a container escape and root on the VM.

It would buy two things, and they are worth stating rather than waving at.

**A second exploit becomes necessary.** With the launching account in the
`docker` group, reaching root needs no exploit at all: `docker run -v /:/host
--privileged` is one command. Under a rootless runtime an escape lands as an
unprivileged user who then needs a working local privilege escalation against
that specific kernel. Two exploits instead of one, and the second has to match
the box in front of it.

**The session is separated from whatever else is on the machine.** This is the
one that decides it, and its value is measurable: it is worth exactly as much as
there is on this devbox that the session does not already reach.

On a devbox in spec - one person's work, and
[§7 of the runbook](building-a-devbox.md#7-keep-the-credentials-off-this-box)
followed - that set is small but not empty. It holds the working trees of every
project other than the one the session was launched for, and it holds **the
model API credential**, which cannot be moved off the box because the host-side
proxy has to read it.

So the question is whether this control protects those, and the answer for both
is no.

The credential: a rootless runtime means running dejima as some account, and the
proxy runs as that same account and reads the credential from that account's
home. An escape landing in the account that launched the session reaches it
exactly as it does now. Protecting it needs the proxy's identity split from the
session's, which is a change in dejima rather than something this repository can
arrange.

The other projects: one account owns all of them, so moving the session out of
your account and into a dedicated one moves the projects with it. Separating
them from each other is per-project Unix users, rejected below on its own
grounds.

Rejected on that basis: the separation carries a real feasibility risk and
covers neither of the things that would have justified it. Not on the grounds
that an escape is unlikely, and not because there is nothing there to protect.

The feasibility risk is live rather than theoretical: dejima builds its own
`iptables` and `ipset` firewall inside the container and needs `NET_ADMIN`,
which may not survive a rootless runtime.

**Revisit if either becomes true.** Both are things you can check, rather than
judgements about who might be attacking:

- dejima gains a way to run the credential proxy under a different identity from
  the session, at which point this control would protect the one item that
  matters;
- dejima stops needing `NET_ADMIN`, which removes the feasibility risk and makes
  the change cheap enough that a small benefit is worth having.

Note what is *not* on that list: a devbox holding several people's work. That is
not a reason to revisit this decision, because such a machine is out of spec for
this tool entirely - see "What this tool assumes".

**Per-project or per-session Unix users.** Buys separation between projects.
Rejected because cross-project code access already exists through the forge
credential, so this addresses the smaller half of the concern while imposing
per-user image stores, per-user daemons and ownership churn. Per-session users
additionally fail quietly, through stale UIDs on git objects and caches.

The half worth closing is agent memory, and a Unix account boundary is not what
closes it. dejima scopes the `projects` and `file-history` mounts, which is
where that control belongs: in the repository that owns the mount.

**Mirroring the LAN DROPs into IPv6 instead of dropping the family.** Rejected
because the list cannot be written. There is no v6 range that means "private",
so the closest anyone can get is dropping `fc00::/7` and leaving the guest able
to reach every neighbour on the prefix the ISP delegated. A rule set that looks
symmetrical and covers nothing is worse than the blanket drop, because it reads
as handled by anyone reviewing it later.

Revisit if the devbox ever genuinely needs IPv6 egress. The work then is to find
out which prefix your own LAN is on and drop that instead, and to know that the
prefix changes when the delegation does - so the rule acquires a way to go stale
that none of the v4 rules have.

**Disabling IPv6 in the guest, with `net.ipv6.conf.all.disable_ipv6`.** Rejected
for the reason every other control here sits on the node: it is a setting on a
machine this model assumes an attacker holds root on, and root sets it back.

It is worse than merely ineffective. It would also make the audit's own IPv6
check pass, so the guest would be certifying its own containment on the strength
of a setting the guest controls - which is the exact failure the whole
verify-by-behaviour design exists to avoid.

**Scheduled rollback.** Rejected because it destroys uncommitted work, which is
the thing a devbox exists to hold. This is the largest single difference from
the sister project, whose entire containment story is that a runner is rebuilt
nightly. Snapshots here stay manual.

**Detection and forensics tooling beyond the audit.** Out of scope. The audit
reports state, not history.

**Changing how dejima runs.** Out of scope in both directions. Container-level
controls belong in dejima. Where this project needs something from there, it is
raised there rather than worked around here.

## This page has a date on it

Every argument above is reasoning about a particular idea of what the adversary
can do, and that idea does not keep. The controls are aimed at a payload nobody
aimed at this machine and at an agent that can be talked into things, and
neither of those descriptions has been getting more reassuring.

Hardening designed against the agent of two years ago is not obviously adequate
against the agent of today, and the honest position is that nobody here can tell
you where the line is. What can be done is to re-read the reasoning on a
schedule rather than when something goes wrong.

**Quarterly**, matching dejima's own cadence, and the argument applies harder
here than there: this is the layer that catches what the layer above fails to
hold, so it is the one where a stale assumption goes unnoticed longest.

What to check, rather than re-argue:

- the revisit conditions on each entry in "Rejected, with reasons". They are
  written as facts to look up, not judgements to re-make, so the review is
  cheap and has an answer;
- whether the sibling directories dejima mounts host-wide - `tasks`, `plans`,
  `sessions`, `backups` - have started being loaded into a session's context at
  startup, which is the property that would make them worth scoping;
- whether anything has changed about what an escape is worth, since that is the
  premise the deprioritisation rests on and not a conclusion of it;
- whether the address families, ports and ranges named on the node still cover
  every way a neighbour of this VM can be addressed. A list bounds only what it
  names, and nothing fails visibly when it names too little.

## What this repository does not claim

It does not prevent root on the devbox. Nothing here tries to.

What it does is bound what a compromised VM reaches, and state that bound in a
form you can check. Everything else follows from taking that limit seriously
rather than dressing it up.
