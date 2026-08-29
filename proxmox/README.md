# Provisioning a devbox on Proxmox

The node-side half: the VM, and the firewall applied to it. All of it in the web
console. The in-VM half is
[docs/building-a-devbox.md](../docs/building-a-devbox.md), the same on any
hypervisor.

## The whole job

**Already have a devbox?** This page is for building one. To bring an existing
box forward, start at
[Updating](../README.md#updating-an-existing-devbox) instead: the upgrade notes
name the rules to change rather than having you re-read the table below.

Five steps, and the two pages interleave: follow this order rather than either
page top to bottom.

| | Do this | Where | Roughly |
| --- | --- | --- | --- |
| 1 | Turn the datacenter firewall on | §1 below | one setting |
| 2 | Create the VM | §2 below | one form |
| 3 | Install Debian | [guest §1](../docs/building-a-devbox.md#1-install-debian) | the usual |
| 4 | **Build the rules, apply them, verify** | §3 below | **the substance of this page** |
| 5 | Finish the guest setup | [guest §2 onward](../docs/building-a-devbox.md#2-addressing-leave-it-on-dhcp-for-now) | one command, then checks |

Then §4 here, whenever you want a snapshot.

**Everything except step 4 is short.** Step 4 is twelve firewall rules entered
into a form, three policy settings, and two verification passes. If you have
done it before, [the rule table](#build-the-group-once) is the whole of it.

**The rules go on after the OS is installed, not before.** The Debian installer
takes its address by DHCP whatever you intend to pin it to afterwards, and a
lease needs a reply back in. Apply the group first, without the DHCP pair from
§3, and the installer simply has no network, which presents as a broken mirror
or a dead link, not as a firewall you switched on ten minutes earlier. Ticking
the Firewall checkbox in §2 is safe on its own.

## What you are building

**A machine you cannot afford to lose, treated as one you might.**

That is the whole difference from a CI runner, which is built to be lost and
rebuilt from a snapshot on a schedule. A devbox holds uncommitted work, so a
rollback on a timer destroys the thing the machine exists to hold, and nothing
reclaims this VM on a cadence.

What follows: containment here is the firewall on this page, plus keeping the
box worth little, plus being able to rebuild it. There is no fourth thing.

**The firewall goes on the node, not in the guest.** Root in the VM can flush
any rule set it can see. It cannot reach one applied to its own tap device.
dejima's own controls are not a second copy of this: they bound what a
*session* reaches, and cannot bound what the *VM* reaches, because they run
inside it.

**It does not prevent root on this VM.** It makes root here worth less: no LAN
to move onto, and a machine whose rebuild cost you have already paid once.
[docs/threat-model.md](../docs/threat-model.md#blast-radius-by-layer) has what
each layer actually grants.

---

## 1. Check the datacenter firewall is on

**Do this first.** A per-VM firewall with the datacenter switch off is read
and enforced nowhere, and nothing about that is visible from the VM: it looks
exactly like a working setup.

**Datacenter → Firewall → Options → Firewall: `Yes`**

If you have to change it, check that nothing else on the node depended on
having no firewall. The datacenter default policy is `ACCEPT` in and out, so
turning it on does not by itself filter anything, but it is worth knowing
before you flip it rather than after.

---

## 2. Create the VM

**Create VM**, and the values that matter:

| Tab | Setting | Value |
| --- | --- | --- |
| General | Name | `devbox`, or whatever you prefer |
| OS | ISO | Debian netinst, current stable |
| System | Qemu Agent | ✓, and see the note below, the tick alone does nothing |
| Disks | Size | 128 GB. A devbox accumulates checkouts, container images and build caches, and it is not rebuilt on a schedule to clear them |
| CPU | Cores | 4 |
| CPU | **Type** | **`x86-64-v3` or better, not the default.** See below; the default cannot run at least one of dejima's harnesses, which requires AVX2 capability |
| Memory | | 16384 MB. dejima builds its image and runs sessions; 8 GB works and is tight |
| Network | Bridge | your normal bridge |
| Network | **Firewall** | **✓: this is the checkbox everything else depends on** |

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

Worth checking rather than assuming, once the guest is up, and worth running
on any devbox built before this section existed, since the alternative is
discovering it as a crash with no output:

```sh
grep -qw avx2 /proc/cpuinfo && echo "  avx2 present" || echo "  NO AVX2 - fix the VM's CPU type"
```

**What a moving address does *not* break.** Not the firewall. Every rule in the
next section keys on a *destination*, except the two inbound rules, which key
on *your* client subnets, and Proxmox applies the whole set to this VM's tap
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

**[docs/building-a-devbox.md §1](../docs/building-a-devbox.md#1-install-debian)**,
then return here for §3. Nothing else from that page is needed yet.

§3 ends by testing the rules from inside the VM, and there is nothing to test
from until an OS is running. That is the whole reason for the detour.

---

## 3. The firewall rules

**This is the primary control.** Everything else in this repository exists to
verify it or explain it.

Twelve rules, built once as a **security group** and applied to each devbox.
Build the group even with one VM: hand-entered copies are two chances to get the
ordering wrong, and one of them to drift later.

The outbound half does the work and stays fixed: six DROPs covering every
address a neighbour can hold, with exceptions above them for the two hosts this
VM genuinely needs. A third joins them if you want dejima's notifications, and
it is the one to be careful with: see [One more, if you want dejima's
notifications](#one-more-if-you-want-dejimas-notifications).

The inbound half is the part that grows, because unlike a CI runner a devbox
offers services you want to reach; keep it legible rather than short.

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
| 7 | out | DROP | - | - | **Dest:** `10.0.0.0/8` | |
| 8 | out | DROP | - | - | **Dest:** `172.16.0.0/12` | |
| 9 | out | DROP | - | - | **Dest:** `192.168.0.0/16` | The three that matter |
| 10 | out | DROP | - | - | **Dest:** `169.254.0.0/16` | Link-local, incl. metadata services |
| 11 | out | DROP | - | - | **Dest:** `100.64.0.0/10` | Carrier-grade NAT, where a tailnet lives |
| 12 | out | DROP | - | - | **Dest:** `::/0` | IPv6, the whole family |

**Set Log level to `info` on rules 7 to 12, and leave it `nolog` everywhere
else.** A packet matching a DROP is this VM trying to reach your network, which
on a working devbox is close to never: its forge and resolver have pinholes
above, and nothing else it does legitimately goes to a private address. So that
log is quiet by construction, and a burst in it is the loudest signal a
compromised devbox produces. It is also written by the hypervisor, about traffic
the hypervisor refused, which puts it somewhere the guest cannot reach.

Logging the *policies* instead would be useless: `policy_out` is ACCEPT, so it
would record this machine's entire internet traffic, and `policy_in` drops
broadcast chatter all day.

Expect noise at first. mDNS, SSDP and NetBIOS all land here on a healthy box.
The signal is not that a drop happened but that a destination appeared which
this VM has never tried before, so read a week of it before deciding what
normal looks like.

**Rules 1 and 2 are added once per client subnet.** Phones and laptops sit on
different wireless networks often enough that assuming one is the wrong
default. Add the rule again for each.

Do not widen the mask instead. A range chosen to span two subnets is not two
subnets, it is every subnet between them, and it will keep being right for
years before it is suddenly very wrong.

**Rule 4 is the one a CI runner never needed.** A devbox pushes over SSH. Miss
it and `git push` hangs against rule 7 rather than failing, which reads as the
forge being down.

**Rule 11 is for a tailnet.** Tailscale numbers its hosts out of
`100.64.0.0/10`, which is none of the three RFC 1918 ranges, so without this
rule a devbox on your tailnet reaches every machine you own anywhere, which is
a wider network than the one rules 7 to 9 were drawn around, not a narrower one.
Add it whether or not you run Tailscale today: it costs nothing on a devbox that
has no overlay, and the day someone installs one is not a day anyone revisits
the firewall.

#### Rule 12, and why IPv6 is dropped whole

**IPv6 has no RFC 1918**, so there is no list of private ranges to mirror: the
family goes whole instead. Worth having even on a network that routes no IPv6,
because every Linux host answers on `fe80::` regardless. The argument is in
[the threat model](../docs/threat-model.md#the-lan-boundary-is-two-boundaries)
and again above `OUT DROP -dest ::/0` in
[firewall.fw.template](firewall.fw.template).

**Do it here, not with `disable_ipv6` in the guest**: that is a setting root in
the guest can put back.

**If the console rejects `::/0`**, enter four rules in rule 12's position
instead: `fe80::/10`, `fc00::/7`, `ff00::/8`, `2000::/3`. Prefer the single
line; four entries are four chances to enter three.

`dejima-devbox-audit reach` checks this one by behaviour, like the rest.

#### Why the front door gets the narrower list

The intuition that SSH is the more dangerous of the two is backwards: same
capability, weaker gate. Basic auth is a password with no rate limiting, no
lockout and no second factor; an SSH key has nothing to guess. So the front door
takes the smaller source range. Argued in full above the inbound rules in
[firewall.fw.template](firewall.fw.template).

Two cheap improvements, since it is the weaker side by construction:
`limit_req` on that nginx location, and a client certificate, which phones
install as a profile and which brings the gate to roughly the strength of an
SSH key.

#### What this list does not bound

Adding a client subnet widens **who can reach this VM**. It does not widen what
this VM can reach, which is the bound rules 7 to 12 fix and the one this
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

#### One more, if you run dejima-guard elsewhere

[dejima-guard](https://gitbox.branderson.io/dejima/dejima-guard) watches this
devbox from a machine that is not this devbox. It connects over SSH, so:

| # | Direction | Action | Protocol | Dest. port | Source / Dest | Why |
| --- | --- | --- | --- | --- | --- | --- |
| 2b | in | ACCEPT | tcp | 22 | **Source:** the guard's IP | The guard collects over SSH |

**Check whether you need it first.** A guard on the admin subnet is already
covered by rule 1 and this adds nothing. It is for a guard living somewhere
else: a container host in another segment, which is where a fleet of them
tends to be.

**One address, not the subnet it sits on.** The guard is one machine, and
naming one machine is the point.

**There is no outbound counterpart, and adding one would be a mistake.** The
guard pulls: it reaches in, and this devbox never reaches out to it. That is
what lets a guard report on a devbox that has been taken: a box that cannot
talk to its watcher cannot silence it. A rule added "for symmetry" would give
that away without looking like it had.

**What it grants is the chance to attempt SSH, not a shell.** The key is
restricted at the guest end, by a forced command and a sudoers rule that name
the same two read-only invocations: see
["Let the guard in" in the guest runbook](../docs/building-a-devbox.md#guard-access).
The guard is a machine holding the evidence about this one, so it is worth
assuming somebody will eventually want it.

#### Two more, if the VM gets its address by DHCP

Skip both if you pinned the address in the guest with `dejima-devbox-static-ip`.
Add both if you did not, including when the address is reserved for you on the
router: reserved or not, the guest still speaks DHCP.

| # | Direction | Action | Protocol | Dest. port | Source / Dest | Why |
| --- | --- | --- | --- | --- | --- | --- |
| 2a | in | ACCEPT | udp | 68 | - | Let the lease reply back in |
| 6a | out | ACCEPT | udp | 67 | - | Let the lease request out |

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
does leave without rule `6a`, but the reply still needs `2a`. Half a working
path renews nothing.

This failure is slow and does not look like a firewall. Nothing breaks at
reboot or at first boot. The VM simply stops renewing, and somewhere up to a
full lease time later it drops off the network.

Rule `2a` lets anything on the segment send to the client port, which is a
spoofed-reply surface. It is close to free: DHCP on a LAN is trust-on-first-use
for every host on that segment whatever the firewall does, so permitting the
reply does not create that exposure. Not using DHCP is still narrower, and
`dejima-devbox-static-ip` exists for it.

#### One more, if you want dejima's notifications

dejima can post a notification when a session finishes or wants an answer, to an
ntfy server. That server is on your LAN, so rule 7 drops the post and the
feature quietly does nothing: no error anywhere you would look, no notification,
and a devbox that appears to have the feature switched off.

One line fixes it, and it is the most dangerous line on this page.

| # | Direction | Action | Protocol | Dest. port | Source / Dest | Why |
| --- | --- | --- | --- | --- | --- | --- |
| 6b | out | ACCEPT | tcp | ntfy's port | **Dest:** ntfy's IP | Post a notification |

Place it with rules 3–6, above the DROPs, and read the rest of this section
before you do. What that destination is decides whether the rule grants one
service or your whole network.

##### Why the obvious version of it hands back the entire boundary

On most home networks ntfy is not a host. It is a name on the reverse proxy that
fronts everything else you run, so its address is the proxy's address and its
port is 443.

**These rules match an address and a port.** They cannot see the `Host` header
or the TLS SNI, and those are the only things that tell `ntfy.example.com` apart
from every other name that proxy serves. A rule naming the proxy on 443 does not
grant ntfy. It grants the dashboards, the NAS web UI, the router, the hypervisor
if it is proxied, and whatever gets added behind that proxy next year by someone
not thinking about this rule. Rules 7 to 10 stay in the list and stop meaning
what this page says they mean.

Nothing catches it afterwards. `dejima-devbox-audit` probes the gateway, the
gateway is still dropped, so it keeps reporting `PASS` on a devbox that can now
reach every service on the proxy. In the console the rule reads as one host, for
as long as anyone looks at it.

##### The two shapes that do not

Both do the same thing: make ntfy a destination the firewall can name, by
putting it on a listener that serves ntfy and nothing else.

**A dedicated port, which is the simpler of the two.** Serve ntfy on `8443` on
the proxy's existing address and open only that port. Every other vhost is on
443 and does not appear on 8443 unless someone puts it there, so the failure
mode is a listener you must add to on purpose rather than one that inherits
everything by default. The cost is that this devbox's ntfy URL carries a port
that no other client uses.

```nginx
# ntfy, alone on 8443. THIS PORT IS A FIREWALL PINHOLE: anything else given a
# server block here becomes reachable from the devbox.
server {
    listen <proxy-ip>:8443 ssl;
    server_name ntfy.example.com;

    ssl_certificate     /etc/ssl/ntfy/fullchain.pem;
    ssl_certificate_key /etc/ssl/ntfy/privkey.pem;

    location / {
        proxy_pass http://<ntfy-backend>:80;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # ntfy holds subscriptions open and streams into them. Without these
        # the publish side works and subscribers see nothing until a timeout.
        proxy_read_timeout 3m;
        proxy_send_timeout 3m;
        proxy_buffering    off;
    }
}

# A name that matches nothing on this port gets nothing, rather than falling
# through to the block above.
server {
    listen <proxy-ip>:8443 ssl default_server;
    ssl_certificate     /etc/ssl/ntfy/fullchain.pem;
    ssl_certificate_key /etc/ssl/ntfy/privkey.pem;
    return 444;
}
```

**A dedicated address**, if you would rather every client kept the same URL. Add
a second IP to the proxy, bind ntfy to it, point the DNS record at it, and open
443 on that address only.

It has a trap the port shape does not, and it is easy to miss: `listen 443 ssl`
binds the wildcard, so **every existing vhost answers on the new address the
moment it exists**, and the pinhole grants all of them exactly as before. Taking
this shape means pinning every other server block to the old address explicitly
(`listen <proxy-ip>:443 ssl;`) and putting a `default_server` returning `444` on
the new one to catch whatever was missed. That is an edit to every vhost on the
box, which is why the port shape is first here.

##### Check it from the VM, rather than assuming it

Three probes. The first must succeed and the other two must not, which is what
makes the set diagnostic rather than reassuring:

```sh
curl -sSf -d "from the devbox" https://ntfy.example.com:8443/<topic>

# another name on the same proxy, reached on the port the rule opens
curl -sS --max-time 5 --resolve other.example.com:8443:<proxy-ip> \
     https://other.example.com:8443/ ; echo "exit $?"

# the port everything else is actually on
timeout 5 bash -c 'exec 3<>/dev/tcp/<proxy-ip>/443' \
    && echo "CONNECTED - the pinhole is wider than ntfy" || echo "blocked"
```

The third is the one that says whether this section worked. If the proxy answers
on 443, the rule names the proxy rather than ntfy and every service behind it is
reachable from this box.

##### Scope the token as well

The rule bounds where the devbox can connect, not what it can do on arrival.
Anything on the box can now publish to any topic on that server and, depending
on how ntfy is configured, subscribe to them.

Give the notify service an access token with write access to the topics it uses
and no read access to anything, so a compromised devbox can post noise and
cannot read the notifications your other clients are getting. That is the half
of this the firewall has no way to express.

##### Where the notify service runs, and why that matters here

On the VM, as a systemd user service, rather than inside the container. So there
is no second list to update: dejima's own egress allowlist is a container
control and never sees the post at all.

Which cuts the other way too. Nothing narrows this pinhole one layer in, the way
that allowlist narrows what a session reaches, so the width of rule `6b` is the
entire answer to what this box can reach on that proxy.

##### And it goes in the group

Not on the VM directly. This is exactly the exception the [hazards
section](#two-hazards-no-rule-covers) is about, and the group is the one place
the whole LAN exposure can be read in one sitting.

### Then apply it, per VM

A security group carries **rules and nothing else**. The policies are not part
of it, so each VM still needs its own:

**VM → Firewall → Options**

| | |
| --- | --- |
| Firewall | `Yes` |
| Input Policy | `DROP` |
| Output Policy | `ACCEPT` |

Inbound denies by default; outbound accepts by default and the LAN is denied
explicitly by the group. That asymmetry is deliberate: deny-by-default earns its
keep where the protected set is enumerable, which the LAN is and the internet is
not. The argument against inverting it is above `policy_out` in
[firewall.fw.template](firewall.fw.template).

Then **VM → Firewall → Add → Security Group**, and select
`dejima-devbox-hardener`. That one entry is the whole rule set. Adding another
devbox later is the same single step, and the order cannot drift between hosts.

#### The ordering trap

**Rules are evaluated top to bottom and the first match wins.** Your pinholes:
rules 3 to 6, plus 6b if you added it: name addresses *inside* the ranges
rules 7 to 12 drop. A pinhole below its DROP is dead, and the VM cannot reach
its forge or resolve anything.

**The console inserts each new rule at the TOP.** So entering them in table
order leaves you the reverse: DROPs on top, pinholes beneath, and a devbox that
cannot reach its forge. Following the table without watching the list is enough
to produce it.

Two ways through. **Drag each rule to the bottom as you add it**, which keeps
the list matching the table at every step and is the easier to check. Or enter
them bottom-up and let the insertions stack into order: quicker, and you are
reading the table backwards while doing it.

Either way, **read the finished list top to bottom against the table** before
you trust it. Nothing else catches this: a dead pinhole looks exactly like a
working firewall until something tries to reach the forge.

Rules 3–6, plus rule `6b` if you took it, are the entire remaining LAN exposure,
and they are why "no LAN access" is not literally true. Every destination is
pinned to one host, on the ports named, and rule `6b` is only that if its
destination serves one service.

Nothing follows rule 12. The public internet is reached by the default policy.

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
| Rule `6b`'s destination and port | A listener serving **only** ntfy | `ss -lntp` on the proxy, and the probes above |
| The forge's hostname | `forge_host` in `/etc/dejima-devbox/config` | `dejima-devbox-bootstrap` asks and writes it |
| Rule 6b's destination **and port** | `ntfy_url`, `[remote-access]` in `~/.config/dejima/config` | `getent hosts <its hostname>` on the VM, and the port out of the URL, not assumed to be 443 |

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

**Nothing checks rule 6b**, and that is worth knowing rather than discovering.
`dejima-devbox-audit` verifies containment: that things which should be
unreachable are, and a missing pinhole is the opposite shape: something that
should be reachable and is not. The audit passes either way. The only symptom
is a phone that stops buzzing, which looks like dejima being broken rather than
like a firewall rule, so check this one by sending a notification and watching
for it.

### Check it, rather than assuming it

**Two passes.** The first reads configuration, the second tests behaviour, and
only the second is proof: a rule that is loaded and a rule that does what you
meant are different claims.

#### Pass one, on the node, with the VM running

Proxmox builds these chains around the tap device, so a stopped VM has none and
their absence would tell you nothing.

```sh
# what is actually loaded right now
sudo iptables -S | grep "tap<vmid>i0"

# the same, for the other address family. Rule 12 lands here and nowhere else
sudo ip6tables -S | grep "tap<vmid>i0"

# what Proxmox would generate from the current config
sudo pve-firewall compile | grep -B2 -A20 "tap<vmid>i0"
```

**Both tables, not just the first.** An IPv6 rule compiles into `ip6tables` and
is absent from `iptables -S`, which shows rule 12 missing whether it is there or
not.

**What you are looking for.** Chains named `tap<vmid>i0-IN` and `-OUT`, holding
your rules in the order you added them. The v4 `-OUT` chain has the four pinhole
ACCEPTs, then the five LAN DROPs, then whatever Proxmox appends for the policy.
The v6 `-OUT` chain has rule 12 and no pinholes, since every pinhole names an
IPv4 address.

| What you see | What it means |
| --- | --- |
| No `tap<vmid>i0` chains at all | The firewall is not applied to this VM. The NIC's Firewall checkbox, the VM's Firewall option, or the datacenter switch: check all three, in that order |
| Chains exist but hold none of your rules | The rules are on a different VM id, or were added at datacenter or node level rather than to this VM |
| A LAN DROP above a pinhole ACCEPT | The ordering trap. The VM will not reach the forge or resolve anything; drag the pinholes above the DROPs |
| Rules present and correct, DNS still failing | The address in rules 5–6 is not the VM's nameserver. The gateway is the usual wrong answer: see "Values that must agree" |
| v4 chain right, `ip6tables -S` empty | Rule 12 was not entered, or the console rejected `::/0` and the error was missed. Nothing about the v4 half will look wrong |

`pve-firewall status` reports the datacenter switch, not these rules.

#### Pass two, from inside the VM

Three must succeed and two must fail. That is what makes the set diagnostic
rather than reassuring.

```sh
try() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null \
        && echo "  CONNECTED  $1:$2" || echo "  blocked    $1:$2"; }

gw=$(ip -4 route show default | awk '{print $3; exit}')
dev=$(ip -4 route show default | awk '{for (i=1;i<NF;i++) if ($i=="dev") print $(i+1); exit}')

try "$gw" 443                  # must be blocked - your own first hop
try <forge-ip> 443             # must connect
try deb.debian.org 80          # must connect - the public internet
getent hosts deb.debian.org && echo "  resolved" || echo "  DNS FAILED"

# must find nobody but this VM - rule 12
sudo ping -6 -n -c 2 -W 1 -I "$dev" ff02::1
```

Nothing needs installing: `bash` opens TCP connections itself, `getent` is part
of libc, and `ping` ships with Debian, which matters on a machine you have not
finished setting up yet.

**The last one asks the whole LAN who is there, over IPv6.** Any reply from an
address that is not this VM's own means rule 12 is not in force, and that the
segment is reachable over a family none of the checks above it touch.

**Both targets are chosen so that naming them writes nothing down.** The
gateway is already in the routing table and `ff02::1` is the same on every
network there has ever been, so neither describes your topology to anyone
reading this box. [docs/reference.md](../docs/reference.md#the-three-verdicts)
has why each is the right probe.

Read them together, because the pattern says which thing is wrong:

- **First one connects** → the firewall is not in force at all. Check the
  Network device's Firewall checkbox and the datacenter switch.
- **Second or third fails while the fourth works** → a pinhole is below the LAN
  DROPs. Check the rule order.
- **Only the last one finds neighbours** → the v4 half is right and rule 12 is
  missing. This is the failure that looks like success from every other angle,
  which is why it has its own probe.
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
Each is reasonable on its own and the set is nobody's decision. [The
notification rule](#one-more-if-you-want-dejimas-notifications) is the worked
example, including the version of it that grants far more than it appears to.
Every LAN exception belongs in §3's table and nowhere else, so the list can be
read in one place and pruned in one place. A rule added directly to the VM rather than
to the group is the one that gets forgotten.


## Why there is no script for this page

A script that runs `qm create` and writes into `/etc/pve/firewall/` is exactly
the kind of artifact people paste into a root shell without reading, and the
blast radius is the whole node: including every VM on it that has nothing to do
with this one. So nothing here asks you to edit a file on the node: where a
console path and a file path both exist, this runbook takes the console path
even when the file would be tidier, because a hand-edited file cannot be checked
as you follow it and puts the hypervisor's configuration outside the tool's
reach.

The in-VM half **is** a script:
[`bin/dejima-devbox-bootstrap`](../bin/dejima-devbox-bootstrap). The difference
is what it can reach if it is wrong.