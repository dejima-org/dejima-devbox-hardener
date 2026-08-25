# Provisioning a devbox on Proxmox

The node-side half: the VM itself and the firewall applied to it. Everything
here is done in the Proxmox web console.

What happens *inside* the VM is
[docs/building-a-devbox.md](../docs/building-a-devbox.md), which is the same on
any hypervisor. Do this page first, then go there.

That split is deliberate, and so is the console-only rule. A script that runs
`qm create` and writes into `/etc/pve/firewall/` is exactly the kind of
artifact people paste into a root shell without reading, and the blast radius
is the whole node, including every VM on it that has nothing to do with this
one. The steps below are short enough to follow and specific enough to check.

Nothing on this page asks you to edit a file on the node. Where a console path
and a file path both exist, this runbook takes the console path even when the
file would be tidier, because a hand-edited file cannot be checked as you
follow it and puts the hypervisor's configuration outside the tool's reach.

The in-VM half **is** a script:
[`bin/dejima-devbox-bootstrap`](../bin/dejima-devbox-bootstrap).

---

## What you are building

A machine you cannot afford to lose, treated as one you might.

That sentence is the whole difference from a CI runner. A runner is built to be
lost: it is rebuilt from a snapshot on a schedule, so anything that gets into it
has until the next rollback and no longer. A devbox holds uncommitted work, so a
rollback on a timer destroys the thing the machine exists to hold. Nothing
reclaims this VM on a cadence.

What follows from that: containment here is the firewall on this page, plus
keeping the box worth little, plus being able to rebuild it. There is no fourth
thing, and no scheduled undo.

**The firewall goes on the node, not in the guest.** Root in the VM can flush
any rule set it can see. It cannot reach one applied to its own tap device.

**dejima's own controls are not a second copy of this.** They bound what a
session inside the container reaches, and they do that well: the container's
egress is deny-by-default and it is given the Docker host's address rather than
the host's subnet, so a session cannot walk your LAN. What they cannot bound is
what the *VM* reaches, because they run inside it. That gap is what this page
closes, and it is why this is worth doing even though dejima already firewalls
itself.

**What this does not prevent.** Root on this VM. Nothing here tries to. What it
does is make root on this VM worth less: no LAN to move onto, and a machine
whose rebuild cost you have already paid once. See
[docs/threat-model.md](../docs/threat-model.md#blast-radius-by-layer) for what
each layer actually grants.

---

## What order to do this in

This page and the guest runbook interleave. Doing them strictly in sequence
does not work, and the reason is worth knowing before you hit it.

1. **§1 and §2 here.** Datacenter firewall on, VM created.
2. **[Install the OS](../docs/building-a-devbox.md#1-install-debian)**, then
   come back. That is the guest runbook's §1 and it is the only part of it you
   need before returning.
3. **§3 here.** Build the rules and apply them. Both halves of its verification
   work at this point, including the ones run from inside the VM.
4. **[The rest of the guest runbook](../docs/building-a-devbox.md#2-addressing-leave-it-on-dhcp-for-now)**,
   from its §2 onward.
5. **§4 here** whenever you want a snapshot.

**The rules go on after the OS is installed, not before**, and that ordering is
load-bearing rather than a matter of taste. The Debian installer takes its
address by DHCP whatever you intend to pin it to afterwards, and a lease needs
a reply back in. Apply the group first without the DHCP pair from §3 and the
installer simply has no network, which presents as a broken mirror or a dead
link and not as a firewall you switched on ten minutes earlier.

Ticking the Firewall checkbox in §2 is safe on its own. It is the group and the
policies in §3 that start dropping things.

---

## 1. Check the datacenter firewall is on

**Do this first.** A per-VM firewall with the datacenter switch off is read
and enforced nowhere, and nothing about that is visible from the VM — it looks
exactly like a working setup.

**Datacenter → Firewall → Options → Firewall: `Yes`**

If you have to change it, check that nothing else on the node depended on
having no firewall. The datacenter default policy is `ACCEPT` in and out, so
turning it on does not by itself filter anything — but it is worth knowing
before you flip it rather than after.

---

## 2. Create the VM

**Create VM**, and the values that matter:

| Tab | Setting | Value |
| --- | --- | --- |
| General | Name | `devbox`, or whatever you prefer |
| OS | ISO | Debian netinst, current stable |
| System | Qemu Agent | ✓ — and see the note below, the tick alone does nothing |
| Disks | Size | 128 GB. A devbox accumulates checkouts, container images and build caches, and it is not rebuilt on a schedule to clear them |
| CPU | Cores | 4 |
| CPU | **Type** | **`x86-64-v3` or better — not the default.** See below; the default cannot run at least one of dejima's harnesses, which requires AVX2 capability |
| Memory | | 16384 MB. dejima builds its image and runs sessions; 8 GB works and is tight |
| Network | Bridge | your normal bridge |
| Network | **Firewall** | **✓ — this is the checkbox everything else depends on** |

The Firewall checkbox is easy to miss and easy to uncheck later without
noticing. If it is off, the per-VM rules do not apply to the interface and the
VM is simply on your LAN.

**Qemu Agent is two halves, and this tick is one of them.** It opens a
virtio-serial channel on the host side; answering on it takes the
`qemu-guest-agent` package inside the guest, which `dejima-devbox-bootstrap`
installs and which tells you if this tick is missing. Leave it on: without the
channel the agent has nothing to attach to, the Summary pane shows no address,
`qm shutdown` falls back to hoping ACPI is acted on, and a snapshot of a
running VM stays crash-consistent.

**AVX2 is needed if you want support for Cline.** Proxmox defaults a new VM to
`x86-64-v2-AES`, which tops out at SSE4.2 and has no AVX at all. The Cline
harness's CLI ships as a Bun-embedded compiled binary whose stock build needs
AVX2. You'll need a CPU type which supports AVX2 if you plan to run Cline in the
VM, and the minimum CPU type which supports this is `x86-64-v3`.

On a v2 guest the binary dies on SIGILL, exit 132, before printing anything, and
Cline publishes no baseline build to fall back to, so the harness being
unavailable is not something the failure tells you.

Three ways to get this wrong:

- **`host` also works and costs more than it looks.** It pins the guest to the
  exact CPU of the node it was created on, so live migration to any node that
  differs stops working. `x86-64-v3` is the portable floor that still carries
  AVX2, and any reasonably modern node meets it.
- **A flags allowlist will not do it.** `cpu: <model>,flags=...` toggles a
  small fixed set and AVX2 is not in it. It has to be the CPU *model*.
- **Changing it on an existing VM needs a full stop and start.** A reboot from
  inside the guest keeps the same QEMU process and therefore the same CPU
  model, which presents as the setting not having taken.

Worth checking rather than assuming, once the guest is up — and worth running
on any devbox built before this section existed, since the alternative is
discovering it as a crash with no output:

```sh
grep -qw avx2 /proc/cpuinfo && echo "  avx2 present" || echo "  NO AVX2 - fix the VM's CPU type"
```

**What a moving address does *not* break.** Not the firewall. Every rule in the
next section keys on a *destination*, except the two inbound rules, which key
on *your* client subnets — and Proxmox applies the whole set to this VM's tap
device, identified by VMID rather than by IP. Nothing anywhere names this VM by
its own address, so a rebuilt VM that comes up on a different one is still
fully firewalled.

That is a real difference from the sister project, where the inbound rule names
a single management host. Scoping inbound to subnets rather than to one address
means a changed lease breaks nothing in the rule set.

What it breaks is you finding the machine: `ssh <you>@<vm-ip>`, and every
later visit. That is reason enough to pin it.

---

## Now install the OS, then come back

The VM exists and has no operating system. Go to
**[docs/building-a-devbox.md §1](../docs/building-a-devbox.md#1-install-debian)**,
install Debian, and return here for §3.

Nothing else from the guest runbook is needed yet. Coming back with a booted VM
is what makes the rest of this page checkable rather than assumed: §3 ends by
testing the rules from inside, and there is nothing to test from until an OS is
running.

---

## 3. The firewall rules

Ten rules, built once as a **security group** and applied to each devbox. Even
with one VM, build the group: hand-entered copies are two chances to get the
ordering wrong and one of them to drift later.

This is the primary control. Everything else in this repository exists to
verify it or to explain it.

### What each part is for

The outbound half is short and does the work. Four DROPs cover every private
range, and above them sit exceptions for the two hosts this VM genuinely needs:
your forge and your resolver. That is the bound this whole project states, and
it does not change however long the inbound list gets.

The inbound half is the part that grows, because unlike a CI runner a devbox
offers services you want to reach. Keep it legible rather than short: every
subnet named here, every port stated, and no rule added anywhere else.

### Build the group once

**Datacenter → Firewall → Security Group → Create**, named
`dejima-devbox-hardener`. Then **Add** these to it, in this order:

| # | Direction | Action | Protocol | Dest. port | Source / Dest | Why |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | in | ACCEPT | tcp | 22 | **Source:** admin subnet | SSH, from wherever you administer |
| 2 | in | ACCEPT | tcp | front door | **Source:** front-door subnet | Remote access, narrower on purpose |
| 3 | out | ACCEPT | tcp | 443 | **Dest:** forge IP | Clone, fetch and push over HTTPS |
| 4 | out | ACCEPT | tcp | 22 | **Dest:** forge IP | Push over SSH |
| 5 | out | ACCEPT | udp | 53 | **Dest:** nameserver IP | The forge's name is internal |
| 6 | out | ACCEPT | tcp | 53 | **Dest:** nameserver IP | Same, over TCP |
| 7 | out | DROP | — | — | **Dest:** `10.0.0.0/8` | |
| 8 | out | DROP | — | — | **Dest:** `172.16.0.0/12` | |
| 9 | out | DROP | — | — | **Dest:** `192.168.0.0/16` | The three that matter |
| 10 | out | DROP | — | — | **Dest:** `169.254.0.0/16` | Link-local, incl. metadata services |

**Rules 1 and 2 are added once per client subnet.** Phones and laptops sit on
different wireless networks often enough that assuming one is the wrong
default. Add the rule again for each.

Do not widen the mask instead. A range chosen to span two subnets is not two
subnets, it is every subnet between them, and it will keep being right for
years before it is suddenly very wrong.

**Rule 4 is the one a CI runner never needed.** A devbox pushes over SSH. Miss
it and `git push` hangs against rule 7 rather than failing, which reads as the
forge being down.

#### Why the front door gets the narrower list

The intuition that SSH is the more dangerous of the two is backwards.

Both put a terminal in front of whoever reaches them, so they do not differ in
capability. They differ in what stands in front. SSH with public-key auth has
nothing to guess and nothing to stuff, and is about as attack-resistant as an
exposed service gets. A web front door behind HTTP basic auth is a password,
and nginx's basic auth brings no rate limiting, no lockout and no second factor
unless they are added deliberately.

Same capability behind a weaker gate, so the front door is the higher-risk
service and takes the smaller source range. Usage tends to land on that split
anyway: you administer over SSH from whatever device is to hand, and you want
the front door for a phone, because that is what it is for.

Two cheap improvements to the front door, since it is the weaker side by
construction:

- `limit_req` on that nginx location, which supplies the rate limiting basic
  auth does not have;
- a client certificate, which phones install as a profile and which brings that
  gate to roughly the strength of an SSH key.

#### What this list does not bound

Adding a client subnet widens **who can reach this VM**. It does not widen what
this VM can reach, which is the bound rules 7 to 10 fix and the one this
project exists to state. The two are different axes and conflating them leads
to refusing a harmless convenience.

What the inbound list does affect is the attack surface of the front door
itself. So the number worth knowing is not how many subnets are listed but how
many addresses they cover. Work it out once, here, and write it at the top of
the group: a /24 is 254 hosts and a /22 is over a thousand, and "three subnets"
sounds identical either way.

`dejima-devbox-audit` cannot do this arithmetic for you, and it is worth saying
why rather than leaving it looking like an omission. The audit runs inside the
VM and the rules are on the node, so it can no more read your inbound list than
it can read the DROPs. It verifies outbound containment by behaviour, which is
possible from inside. Inbound exposure can only be checked from outside, by
trying to connect, and this tool does not go looking for things to connect to.

#### Two more, if the VM gets its address by DHCP

Skip both if you pinned the address in the guest with `dejima-devbox-static-ip`.
Add both if you did not, including when the address is reserved for you on the
router: reserved or not, the guest still speaks DHCP.

| # | Direction | Action | Protocol | Dest. port | Source / Dest | Why |
| --- | --- | --- | --- | --- | --- | --- |
| 2a | in | ACCEPT | udp | 68 | — | Let the lease reply back in |
| 6a | out | ACCEPT | udp | 67 | — | Let the lease request out |

Place `2a` with the other inbound rules and `6a` above the DROPs, as the
numbering suggests. Both name a port and no host, which makes them narrower
than an exception naming your DHCP server: they add no reachable host to the
list above.

**Both or neither.** Rule `6a` alone gets the request out and the VM still
never renews, because the reply arrives from the server's address to the VM's,
which is not the tuple the request created. Connection tracking is unlikely to
match that against `Input Policy: DROP`, so `2a` is what actually lets the
lease complete.

Do not count on rebinding to save you. At T2 the client stops unicasting and
broadcasts to `255.255.255.255`, which none of the DROPs match, so the request
does leave without rule `6a` — but the reply still needs `2a`. Half a working
path renews nothing.

This failure is slow and does not look like a firewall. Nothing breaks at
reboot or at first boot. The VM simply stops renewing, and somewhere up to a
full lease time later it drops off the network.

Rule `2a` lets anything on the segment send to the client port, which is a
spoofed-reply surface. It is close to free: DHCP on a LAN is trust-on-first-use
for every host on that segment whatever the firewall does, so permitting the
reply does not create that exposure. Not using DHCP is still narrower, and
`dejima-devbox-static-ip` exists for it.

### Then apply it, per VM

A security group carries **rules and nothing else**. The policies are not part
of it, so each VM still needs its own:

**VM → Firewall → Options**

| | |
| --- | --- |
| Firewall | `Yes` |
| Input Policy | `DROP` |
| Output Policy | `ACCEPT` |

Inbound denies by default — this VM offers no service anyone should reach, so
the exceptions are short and knowable. Outbound accepts by default, and the LAN
is denied explicitly by the group.

That asymmetry is deliberate, and it is worth resisting the obvious-looking
alternative: deny outbound too, then allow tcp/80, tcp/443 and udp/123. That
breaks things — apt during a first install, and anything else needing a port
nobody listed — and each breakage presents as a network fault rather than as a
firewall rule. It also buys almost nothing: this VM is assumed to be owned by
an attacker with root, and the guarantee being made is *reaches the internet,
not your network*, not *reaches only three ports*. Anyone who owns the box
tunnels over 443 like everybody else.

Deny-by-default earns its keep where the protected set is enumerable, which is
the LAN. The internet is not, and treating it as though it were gets you a rule
set that looks strict and only gets in the way.

Then **VM → Firewall → Add → Security Group**, and select
`dejima-devbox-hardener`. That single entry is the whole rule set, in the order the
group defines, and it is the only firewall rule the VM needs.

Adding another devbox later is that one step. The ordering below was got right
once, in one place, and cannot drift between hosts.

**Order matters within the group, and it is the one thing here that is easy to
get wrong.**
Rules are evaluated top to bottom and the first match wins. Your forge and
your resolver are *inside* the ranges rules 7–10 drop, so if either pinhole
ends up below them it is dead and the VM cannot reach the forge or resolve
anything.

**The console inserts each new rule at the TOP of the list, not the bottom.** So
entering the rules in the order they are written above leaves you with them in
reverse: the four DROPs on top, every pinhole beneath them, and a devbox that
cannot reach its forge. Following the table without watching the list is enough
to produce exactly the failure this section is warning about.

Two ways through it. **Drag each rule to the bottom as you add it**, which keeps
the list matching the table at every step and is the easier one to check. Or
enter them in reverse, from the last row up to the first, and let the insertions
stack into the right order — quicker, and you are reading the table backwards
while doing it, which is its own way to get one wrong.

Either way, **read the finished list top to bottom and compare it against the
table** before you trust it. Nothing else catches this: a dead pinhole looks
exactly like a working firewall until something tries to reach the forge.

Rules 3–6 are the entire remaining LAN exposure, and they are why "no LAN
access" is not literally true. Both destinations are pinned to one host, on
the ports named.

Nothing follows rule 10. The public internet is reached by the default policy.

### Values that must agree

Each of these is entered in two places, and each is silent when the halves
disagree. Read the real value off the machine rather than recalling it. That is
the whole of the advice, and every one of them is easy to get wrong from
memory.

| This | Must equal this | Read the truth from |
| --- | --- | --- |
| Rules 5–6's destination | The VM's **nameserver** | `grep nameserver /etc/resolv.conf` on the VM |
| Rules 3–4's destination | The forge's address | `getent hosts <forge-hostname>` |
| Rule 1's source | The subnets you administer from | your own devices |
| Rule 2's source | The subnets a phone is on | your own devices |
| The forge's hostname | `forge_host` in `/etc/dejima-devbox/config` | `dejima-devbox-bootstrap` asks and writes it |

**Rules 5–6 want the nameserver, not the gateway.** They are the same address
on plenty of networks, which is exactly what makes this worth saying: using
the gateway works for some people and, for everyone else, blocks DNS while
leaving every other check passing. `ip route` gives you the gateway;
`/etc/resolv.conf` gives you the nameserver, and it is the second one that
belongs in these rules.

**The forge pair is the one the audit depends on.** `dejima-devbox-audit` uses
the forge as its positive control: if the forge answers, packets are moving,
and a timeout to the gateway means the firewall rather than a broken network.
Point rules 3–4 at one address and `forge_host` at a name that resolves
elsewhere and the audit reports INDETERMINATE, which is correct but unhelpful.

### Check it, rather than assuming it

On the node, with the VM **running** — Proxmox builds these chains around the
VM's tap device, so a stopped VM has none and their absence would tell you
nothing:

```sh
# what is actually loaded right now
sudo iptables -S | grep "tap<vmid>i0"

# what Proxmox would generate from the current config
sudo pve-firewall compile | grep -B2 -A20 "tap<vmid>i0"
```

**What you are looking for.** Proxmox names the per-VM chains after the tap
interface — `tap<vmid>i0-IN` and `tap<vmid>i0-OUT` for the first NIC — and
your rules appear inside them, in the order you added them. In the `-OUT`
chain that means the four pinhole ACCEPTs first, then the four LAN DROPs,
then whatever Proxmox appends for the policy.

**What each failure looks like.**

| What you see | What it means |
| --- | --- |
| No `tap<vmid>i0` chains at all | The firewall is not applied to this VM. The NIC's Firewall checkbox, the VM's Firewall option, or the datacenter switch — check all three, in that order |
| Chains exist but hold none of your rules | The rules are on a different VM id, or were added at datacenter or node level rather than to this VM |
| A LAN DROP above a pinhole ACCEPT | The ordering trap. The VM will not reach the forge or resolve anything; drag the pinholes above the DROPs |
| Rules present and correct, DNS still failing | The address in rules 5–6 is not the VM's nameserver. The gateway is the usual wrong answer — see "Values that must agree" |

`pve-firewall status` is the quicker sanity check of whether the service is
running and enabled at all, but it says nothing about *these* rules — it is
the datacenter switch it reports on, not your ten lines.

**Both commands describe configuration.** They are worth reading, and they are
not proof: a rule that is loaded and a rule that does what you meant are
different claims. The checks from inside the VM below are the ones that test
behaviour, which is why they follow rather than replace this.

and from inside the VM, once it is up. Three of these must succeed and one
must fail, which is what makes the set diagnostic rather than reassuring:

```sh
try() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null \
        && echo "  CONNECTED  $1:$2" || echo "  blocked    $1:$2"; }

gw=$(ip -4 route show default | awk '{print $3; exit}')

try "$gw" 443                  # must be blocked - your own first hop
try <forge-ip> 443             # must connect
try deb.debian.org 80          # must connect - the public internet
getent hosts deb.debian.org && echo "  resolved" || echo "  DNS FAILED"
```

Nothing here needs installing: `bash` opens a TCP connection on its own and
`getent` is part of libc, which matters on a machine you have not finished
setting up yet.

**The first probe targets your gateway, deliberately, and not some other host
on your LAN.** Naming another host would mean writing down something worth
attacking on the machine this page assumes will be owned. The gateway avoids
that entirely: its address is already in the routing table, so it reveals
nothing; it is guaranteed to be alive, which an arbitrary address is not; and
it sits inside the ranges rules 7 to 10 drop, so with the rules applied it must
be unreachable *as a destination* while traffic *through* it to the internet is
untouched.

Read the four together, because the pattern says which thing is wrong:

- **First one connects** → the firewall is not in force at all. Check the
  Network device's Firewall checkbox and the datacenter switch.
- **Second or third fails while the fourth works** → a pinhole is below the LAN
  DROPs. Check the rule order.
- **Everything fails** → the VM has no working route or DNS, which is a
  networking problem rather than a firewall one. Note that this also makes the
  first probe's "blocked" meaningless: silence proves nothing when nothing is
  getting through. That ambiguity is exactly why `dejima-devbox-audit` reports
  three outcomes rather than two.

**Do this once by hand, then stop doing it by hand.**
[`bin/dejima-devbox-audit`](../bin/dejima-devbox-audit) runs the same checks,
tells the three outcomes apart properly, and a timer re-runs it. Rules get
edited, and a rule widened by accident has no symptom on this VM at all.

---

## The node side is done. Go back to the guest.

Everything above is what a hypervisor does and a guest cannot. The rest is
inside the VM: pinning the addressing, installing the audit and its timer,
keeping credentials off the box, and patching.

**Continue at [docs/building-a-devbox.md §2](../docs/building-a-devbox.md#2-addressing-leave-it-on-dhcp-for-now).**

Come back here only for §4, when you want a snapshot. If you added the DHCP
rules and later pin the address in the guest, you can drop them then - that is
the one thing on this page the guest runbook can change.

---

## 4. Snapshots, and why there is no cadence

Take a snapshot before anything you would not want to undo by hand: a kernel
upgrade, a change to the container runtime, the first run of new tooling.

**VM → Snapshots → Take Snapshot.** Leave *Include RAM* unchecked. You want a
disk state you can return to, not a resumed process tree, and the RAM image
costs the VM's whole memory in storage for nothing you will use.

### There is no scheduled rollback here, and that is the design

This is the single largest difference from a CI runner, and it is worth being
explicit about because the sister project's runbook devotes a long section to
automating exactly what this page refuses to do.

A runner is rebuilt on a timer because nothing on it is worth keeping. Its
whole containment story is that anything which gets in has until the next
rollback. A devbox holds uncommitted work, so a rollback on a timer destroys
the thing the machine exists to hold. There is no cadence that is both safe for
your work and useful against an intruder.

So containment here comes from §3 and from keeping the box worth little. Not
from being able to throw it away.

### What replaces it

**Push more often than you would on a machine you trusted.** The forge is the
only copy a rollback cannot eat, and it is also the only copy an intruder on
this VM cannot quietly alter without it showing up as a push you did not make.

**Know your rebuild cost, by having paid it once.** On a box you cannot roll
back, rebuild time is the real measure of containment: it is what "recover from
a compromise" actually costs you. A rebuild you have never done is an estimate,
and estimates of this are always low. Doing it once, deliberately, converts the
number from a guess into a fact.

**Keep the credentials off it**, so the rebuild is the whole of the recovery
and not the start of it. That part is in
[docs/building-a-devbox.md](../docs/building-a-devbox.md), because it is guest
work.

### Two hazards no rule covers

**Agent forwarding.** `ssh -A` into this VM lends it your keys for the life of
the session, and this is a VM whose threat model says it may be owned. Put
`ForwardAgent no` in your SSH config for this host, and reach anything else
directly rather than through it. This is easy to leave on by accident, because
it is often set globally and never thought about again.

**Exception creep.** A NAS today, a registry next month, a printer after that.
Each is reasonable on its own and the set is nobody's decision. Every LAN
exception belongs in §3's table and nowhere else, so the list can be read in
one place and pruned in one place. A rule added directly to the VM rather than
to the group is the one that gets forgotten.
