# Building a devbox

The guest-side half. Everything here happens inside the VM and is the same on
any hypervisor.

The node-side half is [proxmox/README.md](../proxmox/README.md): creating the
VM and applying the firewall to it. The two halves are separate documents so
that another hypervisor can be added later without touching a single guest-side
step.

**They interleave rather than running one after the other**, and that page's
[order section](../proxmox/README.md#the-whole-job) is the
authoritative version. In short: do its §1 and §2, come here for §1 below and
install the OS, go back for its §3, then return here and carry on from §2.

The reason is that the node firewall's rules are checked from inside the VM,
and there is nothing to check from until an OS is running.

**Already have a devbox?** This page builds one. To bring an existing box
forward, see [Updating](../README.md#updating-an-existing-devbox).

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
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/dejima-org/dejima-devbox-hardener
cd dejima-devbox-hardener
sudo ./bin/dejima-devbox-bootstrap
```

One command. There is no separate install step.

It asks which account will run dejima, installs what dejima needs from the host
(Docker with the `compose` v2 plugin, `python3`, `jq`, `git`) and adds that
account to the `docker` group, clones dejima to `~/dejima`, offers to pin the
addressing, asks for your forge's hostname, installs the audit with its timer,
runs the audit once, and then tells you where that result leaves the host and
how far the account has got with §5's harness step.

Everything needing the network happens before the addressing step, which is the
one thing here that can take the network away.

**Expect it to report FAIL the first time**, unless you have already applied the
node firewall. That is correct: nothing is contained yet.

## 5. Install dejima

### The harness goes on this box first, and signs in here

dejima runs sessions in a container and takes two things from the account that
launches them: a harness installed on this VM, and that harness already signed
in to the model backend. Do both before dejima's first session. They fail
differently and neither failure names itself.

**Signed in, because the credential proxy has to have something to hold.**
dejima keeps the harness's credential out of the container: a host-side proxy
reads the real one and the container gets a placeholder. That proxy runs as this
account and reads this account's copy, so an account that has never signed in
leaves it holding nothing, and sessions fail at the backend with the container
looking like the broken part.

**Installed and run here, because the mounts are host paths.** dejima bind-mounts
the harness's state directory into the container, and it has to exist on this
side first. A bind mount whose source is missing is either created as an empty
directory owned by root or refused outright, depending on how it is declared.
Neither of those says "the harness has never run on this account", and the first
leaves root-owned directories in a home that is not root's.

**Which harness, and therefore which paths, is dejima's to say.** It supports
more than one, and the set changes there rather than here, so this page names no
directory as the answer. For Claude Code the state directory is `~/.claude` and
the credential inside it is `~/.claude/.credentials.json`; another harness keeps
its own, somewhere of its own choosing. What holds across all of them is the
shape of the requirement above.

The check is the harness's own, not this repository's: as the account that will
run dejima, start it once and confirm it opens a session rather than asking you
to log in. Installing it is that project's step, and its docs are where the
route belongs.

Then the rest of this section, in this order: the harness, signed in, and only
then `install.sh`, which writes its hooks into the state directory that now
exists.

The credential this creates is the one [§8](#8-keep-the-credentials-off-this-box)
cannot tell you to move off the box, for the same reason it has to be here: the
proxy reads it locally.

### Then dejima itself

The source is already at `~/dejima`. Installing it is dejima's step, not this
tool's:

```sh
cd ~/dejima && ./install.sh          # as your own account, not root
```

Log out and back in first if bootstrap added you to the `docker` group. A shell
that was already open does not have it, which presents as Docker being broken
rather than as a group that has not taken effect.

`install.sh` symlinks the CLIs into `~/.local/bin` and the hooks into
`~/.claude/hooks`, and writes a starter `~/.config/dejima/config`. Put
`~/.local/bin` on your `PATH`. What comes after that - a forge, a workflow, a
push credential - is in
[dejima's README](https://github.com/dejima-org/dejima#setup). A fresh
config pushes nowhere until you choose one.

The line is deliberate. This repository hardens the machine dejima runs on, and
what `install.sh` does to your account is dejima's to define and to change; a
copy of that contract kept here would go stale without anything noticing.

### If you want notifications, they need a rule on the node

dejima's notifications go to an ntfy server, and an ntfy server on your own
network is one of the things the node firewall drops. The notify service runs
here, on the VM, as a systemd user service rather than inside the container, so
what a failed post produces is a line in `journalctl --user -u` for that unit
and nothing anywhere you were looking. No delivery, no error in the session, and
a feature that reads as switched off rather than as firewalled.

The rule is [one more, if you want dejima's
notifications](../proxmox/README.md#one-more-if-you-want-dejimas-notifications),
and it is worth reading in full before adding it rather than after. **The
obvious version of that rule gives this VM every service on your reverse
proxy**, because the firewall matches an address and a port and cannot see which
name the request was for. That widening is invisible from here: the audit keeps
reporting `PASS`, because the gateway it probes is still dropped.

Because that service runs on the VM and not in the container, dejima's own
allowlist has nothing to do with it. There is no second list to update, and
equally nothing one layer in that narrows the rule if it is too wide.

## 6. Verify

```sh
sudo dejima-devbox-audit            # both halves
sudo dejima-devbox-audit reach      # containment only
sudo dejima-devbox-audit radius     # what root here would get
```

All three need root: the config is `0640 root`, and the radius report stats
files in the home of the account that runs dejima. It reads that account from
the config rather than from `$HOME`, which under `sudo` and under the timer is
root's - and root's home on a devbox holds nothing, so the report would have
read `none found` on a box full of credentials.

`reach` reports one of three things, and the third is the one to understand:

| | |
| --- | --- |
| `PASS` | The gateway is unreachable **and** the network works. Both halves are needed. |
| `FAIL` | Something answered. The rules are not applied, or an exception sits above them. |
| `INDETERMINATE` | Nothing answered, including things that should. Not a pass. |

`INDETERMINATE` exists because a timeout has two causes and the audit cannot
tell them apart on its own. Reporting it as success would be the one failure
that matters: a check believed when it does not know.

**`reach` runs a second check, on IPv6, and reports it on its own line.** The
node's DROPs name IPv4 ranges and match none of that traffic, so a VM that
reaches the whole LAN over IPv6 passes every check above with nothing to show
for it. This one asks the segment who is there and counts the answers. It uses
`ping`, from `iputils-ping`, which §5's bootstrap installs: without it the
check reports `INDETERMINATE`, which is again not a pass.

If it says `FAIL`, the fix is rule 12 on the node, not a sysctl in here. See
[the threat model](threat-model.md#the-lan-boundary-is-two-boundaries) for why
that distinction is not pedantry.

## 7. Let the guard in, if you run one

<a id="guard-access"></a>

Skip this if you do not run
[dejima-guard](https://github.com/dejima-org/dejima-guard).

It collects from this box over SSH. Two things make that worth as little as
possible to whoever eventually takes the guard: a forced command, and a sudoers
rule naming the same two commands.

**Two halves on two machines.** The sudoers rule is below, on this box. The key
is installed *from the guard*, because that is where the key is: it is
generated there and never leaves. Do this half first, or the guard's own check
of its access will fail on a rule that is not there yet.

```sh
sudo tee /etc/sudoers.d/dejima-guard >/dev/null <<'SUDOERS'
user ALL=(root) NOPASSWD: /usr/local/sbin/dejima-devbox-audit reach, /usr/local/sbin/dejima-devbox-audit drift --state
SUDOERS
sudo chmod 0440 /etc/sudoers.d/dejima-guard
sudo visudo -c
```

Substitute your own account for `user`. `visudo -c` before you log out: a
sudoers file that will not parse takes sudo down with it, and this box has no
root password to fall back on.

**Then the key, run on the guard rather than here**, as yourself: it connects
with your own credentials, and installs the guard's key rather than using it:

```sh
sudo -u dejima-guard dejima-guard-install-key you@devbox
```

As the guard's own account, because that is who owns the key it installs and who
has to be able to read it afterwards. The guard's README is authoritative for
that machine.

That writes the restricted line in a single append and then proves the
restriction: two commands that must work, two that must come back `refused`.
Watch those four results. A restriction nobody tried is a restriction nobody
has, and this one stands between a key taken off the guard and a shell on the
box the guard holds the evidence about.

By hand, if you are not using that tool, the whole line is:

```
command="/usr/local/sbin/dejima-guard-shell",no-port-forwarding,no-agent-forwarding,no-pty,no-X11-forwarding ssh-ed25519 AAAA…the guard's public key
```

Append it **with the options already on it**, in one write. `ssh-copy-id`, or
copying the key and adding the restriction afterwards, leaves an unrestricted
key live in the gap between the two steps.

**Why a wrapper rather than the key naming the audit directly.** The obvious
line is `command="dejima-devbox-audit ${SSH_ORIGINAL_COMMAND##* }"`, taking the
last word of what was asked for. It does not work: `drift --state` becomes
`--state`, which is not a subcommand, so drift collection fails on every cycle
while `reach` keeps working, and the box looks watched when half of it is not.

`dejima-guard-shell` whitelists the two exact commands instead. Whitelisting
says what may run; sanitising tries to describe what may not, and gets it wrong
in ways that are quiet.

**Why the sudoers line names arguments.** `NOPASSWD: /usr/local/sbin/dejima-devbox-audit`
alone would also permit `drift --accept`, which rewrites the baseline, so a key
taken off the guard could tell the devbox that whatever is on it now is normal.
The two exact invocations grant collection and not that.

**If you test by hand, pass `-o IdentitiesOnly=yes`.** `-i` *adds* a key to the
ones ssh offers rather than restricting it to that one, so your own key, or an
agent holding it: authenticates instead, no forced command applies, and every
check reports the restriction missing when it is fine.

```sh
ssh -i guard_key -o IdentitiesOnly=yes you@devbox 'dejima-devbox-audit reach'
ssh -i guard_key -o IdentitiesOnly=yes you@devbox 'cat /etc/shadow'   # refused: ...
```

The node also has to let that host reach port 22:
[proxmox/README.md](../proxmox/README.md#one-more-if-you-run-dejima-guard-elsewhere)
has the rule, and it is unnecessary if the guard is already on your admin
subnet.

## 8. Keep the credentials off this box

Push with a **deploy token scoped to the repositories this box works on**, not
with your personal key. The difference shows up exactly once, on the day the box
is owned: a scoped token is revoked and reissued, and a personal key is every
repository and every host that trusts it.

**Do not give a session push access to a forge it is not being used to push
to.** A session's forge is the one you chose; everywhere else is where its
dependencies and its reading live. dejima blocks GitHub push by default for
that reason and states the argument in full, including what an unsolicited pull
request costs the people receiving it, at [GitHub push: blocked by
default](https://github.com/dejima-org/dejima/blob/main/docs/security.md#github-push-blocked-by-default-optional-opt-in).
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

### The one you cannot move

**The model API credential stays on this box, and nothing in this runbook
changes that.**

dejima keeps it out of the container on purpose: `~/.claude/.credentials.json`
is never mounted, and a host-side proxy holds the real token while the container
sees a placeholder. So a compromised *session* can use the API while it runs but
cannot walk off with the credential.

The proxy has to read that file, and the proxy runs here. Anything with root on
this devbox has it, and that is the step which turns "can use the API until this
session ends" into "holds the token and can use it from anywhere, afterwards".

There is no configuration in this repository that helps. What is left is the
ordinary answer for a credential you cannot remove: know it is there, and know
what to do if the box is ever suspect. **Rotate it** - sign out and back in on
the host, which replaces the stored token - and treat it as the first thing to
rotate rather than an afterthought.

It is not the only thing here whose loss would reach past this machine. Source,
uncommitted work, notes, anything else in the filesystem can be copied out too,
and some of that matters as much. Two things put this one first in the queue
anyway. It is a **standing capability rather than a copy of data**: what leaves
with it is the ability to keep acting as you afterwards, not a snapshot of what
was there at the time. And it sits at a **known path with a known name**, which
makes it one of the easiest things on the box to find and among the first a
prompt injection or a supply-chain payload would go looking for.

## 9. Keep the kernel and the runtime patched

This is the whole of the response to container escape, and it is deliberate. An
escape gets root, which is more than the container had, and root on this VM is
already inside the boundary the node runbook's §3 draws - a boundary that holds
however root was reached. [The threat
model](threat-model.md#why-container-escape-is-deprioritised) has the reasoning
in full.

```sh
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Unattended upgrades install the fix. **They do not reboot into it**, and a
kernel fix that is installed but not running is not a fix. That is why
`dejima-devbox-audit radius` prints the running kernel against the newest
installed one, and says so when they differ.

## 10. Snapshot again

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
