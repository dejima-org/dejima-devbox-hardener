# Building a devbox

The guest-side half. Everything here happens inside the VM and is the same on
any hypervisor.

The node-side half is [proxmox/README.md](../proxmox/README.md): creating the
VM and applying the firewall to it. **Do that page first, through the end of
its §3, then come back here.** The two halves are separate documents so that
another hypervisor can be added later without touching a single guest-side
step.

---

## 1. Install Debian

A netinst image, current stable. Nothing unusual is wanted: no desktop, no web
server, and the SSH server task if you want to reach the machine before you
have finished setting it up.

Tick **standard system utilities** in tasksel. Leaving it unticked produces a
host without `dbus`, which then breaks things far from where the cause was, and
the failure looks nothing like a missing package.

## 2. Addressing: leave it on DHCP for now

The installer will not ask. With a DHCP server on the segment it configures the
interface and moves on.

**Do nothing about it here.** §4's `dejima-devbox-bootstrap` offers to pin this
host to the address it already has, read off the running interface rather than
typed, so nothing has to be transcribed and nothing about reachability changes
at the moment it runs.

Two things it cannot do for you:

- **Reserve the address**, on your DHCP server or by putting it outside the
  pool. Until that is done the server is free to hand the same one to something
  else.
- **Prove it survives a restart**, which is the only real test of an addressing
  change. §3 takes a snapshot first, so finding out costs nothing.

**If you keep DHCP**, including an address reserved for you on the router, the
node firewall needs [two more
rules](../proxmox/README.md#two-more-if-the-vm-gets-its-address-by-dhcp). Both
of them. A reservation does not stop the guest speaking DHCP, and the outbound
rule on its own gets the request out while the lease still never renews.

## 3. Snapshot before any of this touches the machine

**VM → Snapshots → Take Snapshot**, named `preflight`. No RAM.

This is the last moment the machine is a plain Debian install. Everything after
it is this repository's doing, and a snapshot taken here is what lets you find
out whether a step works by trying it rather than by reasoning about it.

## 4. Build it

```sh
git clone <your-forge>/dejima/dejima-devbox-hardener
cd dejima-devbox-hardener
sudo ./bin/dejima-devbox-bootstrap
```

One command. There is no separate install step.

It checks its prerequisites, offers to pin the addressing, asks for your forge's
hostname, installs the audit with its timer, runs the audit once, and then tells
you what it could not do for you.

**Expect it to report FAIL the first time**, unless you have already applied the
node firewall. That is correct: nothing is contained yet.

## 5. Verify

```sh
sudo dejima-devbox-audit            # both halves
sudo dejima-devbox-audit reach      # containment only
sudo dejima-devbox-audit radius     # what root here would get
```

All three need root: the config is `0640 root`, and the radius report stats
files in root's own home.

`reach` reports one of three things, and the third is the one to understand:

| | |
| --- | --- |
| `PASS` | The gateway is unreachable **and** the network works. Both halves are needed. |
| `FAIL` | Something answered. The rules are not applied, or an exception sits above them. |
| `INDETERMINATE` | Nothing answered, including things that should. Not a pass. |

`INDETERMINATE` exists because a timeout has two causes and the audit cannot
tell them apart on its own. Reporting it as success would be the one failure
that matters: a check believed when it does not know.

## 6. Keep the credentials off this box

Push with a **deploy token scoped to the repositories this box works on**, not
with your personal key. The difference shows up exactly once, on the day the box
is owned: a scoped token is revoked and reissued, and a personal key is every
repository and every host that trusts it.

**Do not give a session push access to a forge it is not being used to push
to.** A session's forge is the one you chose; everywhere else is where its
dependencies and its reading live. dejima blocks GitHub push by default for
that reason and states the argument in full, including what an unsolicited pull
request costs the people receiving it, at [GitHub push: blocked by
default](https://gitbox.branderson.io/dejima/dejima/src/branch/main/docs/security.md#github-push-blocked-by-default-optional-opt-in).
It is not restated here, so that there is one copy of it to keep right.

**Do not forward your agent in.** `ssh -A` lends this VM your keys for the life
of the session, and this is a VM whose threat model says it may be owned. In
your SSH config, for this host:

```
Host <your-devbox>
    ForwardAgent no
```

Worth setting explicitly even if you think you never use `-A`: agent forwarding
is often enabled globally years earlier and never thought about again.

`dejima-devbox-audit radius` lists what is currently reachable here, so run it
once after this section and see whether the list is shorter than it was.

## 7. Keep the kernel and the runtime patched

This is the whole of the response to container escape, and it is deliberate.
[The threat model](threat-model.md#why-container-escape-is-deprioritised)
explains why nothing structural is done about it: an escape would land in an
account that holds less than the session already had.

```sh
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Unattended upgrades install the fix. **They do not reboot into it**, and a
kernel fix that is installed but not running is not a fix. That is why
`dejima-devbox-audit radius` prints the running kernel against the newest
installed one, and says so when they differ.

## 8. Snapshot again

**VM → Snapshots → Take Snapshot**, named `clean`. No RAM.

Two snapshots, and they answer different questions. `preflight` is where you go
back to when you want to know whether the runbook works from nothing. `clean` is
where you go back to after a session did something you do not want to keep.

## What is deliberately not here

**A rollback cadence.** A CI runner is rebuilt nightly because nothing on it is
worth keeping. This machine holds uncommitted work, so a scheduled rollback
destroys the thing it exists to hold. Snapshots stay manual, and pushing to the
forge more often than you would on a machine you trusted is what takes their
place.

**Anything that separates a container escape from root on this VM.** Rootless
runtimes and per-project Unix users were both weighed and rejected, with
reasons, in [the threat model](threat-model.md#rejected-with-reasons).

---

Next: nothing. The node half is done, this half is done, and the timer keeps
checking. If you want to know what any of it actually buys, that is
[docs/threat-model.md](threat-model.md).
