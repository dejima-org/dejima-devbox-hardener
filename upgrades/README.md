# upgrades

One file per version. `000N-slug.md` is what an operator has to do to reach
version `N` from version `N-1`, and there is one for every version including the
ones that need nothing: an absent file would be indistinguishable from a file
nobody wrote.

`dejima-devbox-upgrade` reads these. So does a person, and the file is written
for the person; the header exists so the tool can sort, filter and check without
the prose having to be machine-readable.

## Why this exists at all

dejima has no equivalent and does not need one. Its containers are short-lived,
only the tip of `main` is supported, and `git pull` closes any gap that opens.

A devbox is the opposite. It is a long-lived VM pinned to the moment it was
built, its hypervisor rules were entered by hand in a console no `git pull` can
reach, and a snapshot restore can move it *backwards* without anybody deciding
to. Nothing about it converges on the current version on its own, so the gap has
to be measured and closed deliberately.

## The header

```
---
version: 2
title: The LAN boundary gains IPv6 and the CGNAT range
layers: node guest
snapshot: required
verify-node: dejima-devbox-audit reach
---
```

| Key | Means |
| --- | --- |
| `version` | The version this upgrade arrives at. Must match the filename. |
| `title` | One line, shown in `status`. |
| `layers` | `node`, `guest`, both, or `none`. Which halves need work. |
| `snapshot` | `required`, `recommended`, or `none`. See below. |
| `verify-node` | Optional. A command that passes only if the node-side work is actually in force. |

## Two version numbers, not one

The guest half and the node half are tracked separately, in
`/etc/dejima-devbox/state`, because they are known in different ways.

`guest_version` is written by `dejima-devbox-bootstrap` when it installs. It is
a record of something this repository did, so it is as reliable as the install.

`node_version` is written by `dejima-devbox-upgrade mark-node`, by an operator
saying they did the console work. Nothing in the guest can read the hypervisor's
rules, which is the whole reason those rules are worth having, so this is an
assertion, and the tool treats it as one. Where an upgrade names a
`verify-node` command, the tool runs it and will contradict the assertion.

Keeping them apart is what makes a snapshot restore legible. Restore a devbox to
an image from before an upgrade and `guest_version` goes backwards while
`node_version`, which lives on the hypervisor, does not. The pair disagreeing is
a fact worth reporting; a single number would have quietly averaged it.

## `snapshot:`

`required` means the change is lost without a new snapshot, or that an old
snapshot becomes dangerous to restore once the change is made.

A devbox has no scheduled rollback: that is
[rejected, with reasons](../docs/threat-model.md#rejected-with-reasons), because
rollback destroys uncommitted work. So an upgrade is not undone on a timer here
the way it is on a CI runner. What it *is* exposed to is a manual restore: a
snapshot taken before an upgrade will still boot, still pass its own checks, and
still be missing the thing the upgrade added.

Take a fresh snapshot after upgrading, and prefer deleting the pre-upgrade one
to keeping it. A snapshot is a security posture with a date on it.
