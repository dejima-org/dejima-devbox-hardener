---
version: 1
title: Baseline, for a devbox built before versions existed
layers: none
snapshot: none
---

# v1 — the baseline

Nothing to do. This version exists so that "no version recorded" has a name and
a place to be written down, rather than being a gap the tooling has to guess
about.

Every devbox built before `VERSION` existed is a v1 devbox. That is true whether
it was built the week this repository started or the week before the change that
introduced versioning, because until then there was one supported state — the
tip of `main` — and no way to be at any other.

## Establishing where you are

`dejima-devbox-upgrade status` on a host with no `/etc/dejima-devbox/state` will
tell you it predates version tracking and stop there. It does not assume v1,
because a host that is *actually* at v1 and a host whose state file somebody
deleted are the same thing from in here, and picking the friendlier reading is
how a check comes to be believed when it does not know.

To record it, run the guest half of the next upgrade. `dejima-devbox-bootstrap`
writes `guest_version` from this repository's `VERSION` file, so a host that has
been bootstrapped from a checkout is at that checkout's version by
construction — there is nothing to type and nothing to get wrong.

For the node half, read `0002` and the ones after it, do the console work each
one describes, and record it with `dejima-devbox-upgrade mark-node`. There is no
shortcut, because there is nothing in the guest that can read the hypervisor.

## If you are not sure your host is at v1

Then say so with the tool rather than assuming, and check the two things a v1
host is most likely to be wrong about:

```sh
sudo dejima-devbox-audit          # both halves, as they stand
```

A v1 host in good order reports `PASS` on the v4 half. It has no v6 half at all,
because that check arrived in v2 — so an old audit reporting a clean `PASS` is
reporting on less than a current one would. That is precisely the situation
versions exist to make visible.
