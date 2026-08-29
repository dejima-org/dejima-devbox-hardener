# Upgrading a devbox that already exists

A devbox is a long-lived VM pinned to the moment it was built. Half its controls
were entered by hand in a hypervisor console, and the other half were installed
from a checkout that has since moved on. Neither half updates itself, and one of
them can move *backwards* without anybody deciding to.

So this page, and the [`upgrades/`](../upgrades/) directory it describes.

## Doing an upgrade

```sh
git -C ~/dejima-devbox-hardener pull
cd ~/dejima-devbox-hardener
./bin/dejima-devbox-upgrade status
```

`status` from a **checkout** is the authoritative answer. The installed copy at
`/usr/local/sbin/dejima-devbox-upgrade` only knows the upgrades that existed
when it was installed, so it cannot tell you about a version released since,
and it says so rather than reporting "up to date" about versions it has never
heard of.

Then, for each outstanding version, in this order:

1. **`dejima-devbox-upgrade show N`** and read it. Node work first: the guest
   half often installs the check for the node half, and running it against rules
   that do not exist yet produces a `FAIL` that is correct and misleading.
2. **The console work**, in the Proxmox web UI.
3. **The guest work**, usually `sudo ./bin/dejima-devbox-bootstrap` from the
   pulled checkout. Bootstrap is idempotent; Enter at every prompt keeps what
   you have.
4. **`sudo dejima-devbox-upgrade mark-node N`**, which verifies before it
   records.
5. **A fresh snapshot**, if the note says `snapshot: required`.

## Downtime is a scheduled event

On a devbox it is announced, work is drained first, and it does not arrive as a
side effect of a step described as changing nothing. That is the difference from
the sister project, where a runner is rebuilt on a timer and nobody is told.

So every upgrade note declares what it costs:

| | |
| --- | --- |
| `downtime: none` | Nothing here needs the VM stopped or a session interrupted |
| `downtime: window` | Some step does. The note says which, and the rest is live-safe |

`dejima-devbox-upgrade status` prints it too, so a window can be planned before
anyone opens a note.

**In practice the window is the snapshot**, and only the snapshot. A clean one
means stopping the VM; a snapshot of a running machine is crash-consistent,
which is a different and weaker thing. Console rules apply immediately and touch
nothing in the guest. The guest steps are deliberately live-safe: bootstrap
installs only what is absent rather than upgrading what is present, because
`apt-get install docker.io` on a box that already has it will happily take a
newer version and restart the daemon: killing every running session, from a
command documented as safe to re-run.

That is the shape to preserve when adding an upgrade. Anything needing the box
down should be **isolatable as a quick flip to a new state**, batched with the
other such steps, rather than spread through a procedure so that the whole of it
has to happen inside the window.

## Snapshots, and the direction this project cannot roll back

There is no scheduled rollback here. That is
[rejected, with reasons](threat-model.md#rejected-with-reasons): rollback
destroys uncommitted work, which is the thing a devbox exists to hold. So an
upgrade is not undone on a timer the way it is on a CI runner.

What it *is* exposed to is you, later, restoring a snapshot from before it.

**Take a fresh snapshot after upgrading, and prefer deleting the pre-upgrade one
to keeping it.** A snapshot is a security posture with a date on it, and an old
one is a bootable copy of whatever the upgrade fixed. If you keep it, name it so
the date is unmissable in the list.

If you do restore an old one, `dejima-devbox-upgrade status` will report
`guest_version` behind `node_version` and tell you to re-run bootstrap. That is
the pair disagreeing on purpose, and it is the only warning you will get.

## The two version numbers

`/etc/dejima-devbox/state`:

```
guest_version=2
node_version=2
node_asserted=2026-08-25
node_verified=yes
```

**`guest_version`** is written by `dejima-devbox-bootstrap` from the checkout's
`VERSION` file. It records something this repository did, so it is as good as
the install was.

**`node_version`** is written by `dejima-devbox-upgrade mark-node`, by you,
saying you did the console work. Nothing in this guest can read the
hypervisor's rules: that is what makes those rules the primary control, so it
is an assertion and the tool treats it as one.

They are separate because they are known in different ways, and because their
disagreeing is informative:

| | Means |
| --- | --- |
| `node` behind `guest` | Console work outstanding. The ordinary case after a `git pull`. |
| `guest` behind `node` | You restored a snapshot older than your node rules. The node half does not roll back with the guest. |

A single number would have averaged both into silence.

## Where the assertion gets checked

An upgrade note may declare a `verify-node` command: something that passes only
if the console work is actually in force. For v2 that is
`dejima-devbox-audit reach`, whose IPv6 half is a behavioural test of the exact
rule the upgrade asks you to add.

Two consequences worth stating plainly:

- `mark-node` **runs the check first and refuses to record a claim the machine
  contradicts.** `--force` overrides it and records the result as unverified, so
  `status` keeps saying so rather than forgetting.
- **A check that cannot tell is not a check that failed.** The contract is exit
  `0` for in force, `2` for could-not-determine, anything else for not in force.
  `reach` and `drift` both exit `2` on `INDETERMINATE`, and `mark-node` records
  the assertion as unverified rather than refusing it: telling an operator
  their console work is missing on the strength of a check that could not see
  would be wrong in the alarming direction.
- **The command is looked up on `$PATH` first, then beside the tool.** The
  fallback is what makes a checkout work on a box where nothing is installed
  yet. The sister project shipped without it and the tool could not find
  itself.
- `status` re-runs the checks for everything you have already recorded. An
  assertion that was true in June and is not true now is a rule somebody removed,
  and that is worth finding out from a tool rather than from an incident.

Not every upgrade can have one. Where the node-side change has no observable
consequence from inside the guest, the note declares no check and the tool says
so: *"v3 declares no check, so this is your word for it."* That is a weaker
claim and is labelled as one.

## Why this project has one and dejima does not

dejima's containers are short-lived and only the tip of `main` is supported. A
gap opens, `git pull` closes it, and the next container starts from the closed
state. Nothing is pinned, so nothing drifts.

Every one of those sentences is false here:

| | dejima | a devbox |
| --- | --- | --- |
| Lifetime | one session | months |
| Where the controls live | in the image, rebuilt each run | half in the guest, half typed into a console |
| How a gap closes | `git pull` | a person, deliberately, on two machines |
| Can it move backwards? | no | yes: a snapshot restore |

The last row is the one that makes versioning necessary rather than tidy. A
devbox restored from a snapshot taken before an upgrade boots cleanly, passes
its own checks, and is missing whatever the upgrade added. Nothing about it
looks wrong.

## Adding an upgrade, if you are changing this repository

1. Bump `VERSION`.
2. Write `upgrades/000N-slug.md` with the header
   [documented here](../upgrades/README.md#the-header).
3. Give it a `verify-node:` if the node-side change has any consequence
   observable from inside the guest. Prefer an existing audit check to a new
   one.
4. Set `downtime:` honestly. `window` if any step needs the VM stopped or a
   session interrupted, and say **which** step: an operator who has to guess
   schedules the whole procedure into the window instead of the one part that
   needs it.
5. Keep the guest steps live-safe where you can. Installing only what is absent,
   rather than upgrading what is present, is the difference between a re-runnable
   command and one that restarts Docker under somebody's session.
6. Write it for a person who has not read the diff and is standing at a console.

**Write one for every version, including versions that need nothing.** A missing
file and a file saying "nothing to do" are the same thing to a reader who has to
go looking, and this repository's convention is that a choice not to act is
recorded where the absence is.
