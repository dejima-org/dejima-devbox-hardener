# Security policy

## What dejima-devbox-hardener claims

It bounds what a compromised developer VM can reach on your network, and
reports what that bound is.

It does not prevent root on that VM, and nothing here tries to. It does not make
running agent-authored code safe. It does not roll anything back: unlike a CI
runner, a devbox holds uncommitted work, so there is no scheduled undo and no
state this tool restores.

The controls are the hypervisor firewall, which this repository documents but
cannot apply from inside the guest, and an audit that verifies the firewall by
behaviour because the rules live where the guest cannot read them.

[docs/threat-model.md](docs/threat-model.md) states what each layer grants, and
which stronger options were rejected and why.

## Reporting a vulnerability

Email **dejima@branderson.io**. Please do not open a public issue for a
vulnerability; the tracker is public, and a report there is a disclosure.

Useful things to include:

1. what an attacker gets;
2. the steps to reproduce it;
3. the commit you tested.

## The rest of the policy

What is promised in return, the support position, supported versions and
warranty are set once for the whole organisation and are not restated here:

https://gitbox.branderson.io/dejima/dejima/src/branch/main/SECURITY.md
