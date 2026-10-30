# Security policy

## What dejima-devbox-hardener claims

It bounds what a compromised developer VM can reach on your network, and
reports what that bound is.

**On your network** is the whole of the claim. It does not bound egress to the
internet, and nothing on the VM does: outbound traffic to public addresses is
permitted by design. Exfiltration and command-and-control are out of scope, and
a compromise here can phone home. What is bounded is where it can spread.

It does not prevent root on that VM, and nothing here tries to. It does not make
running agent-authored code safe. It does not roll anything back: unlike a CI
runner, a devbox holds uncommitted work, so there is no scheduled undo and no
state this tool restores.

The controls are the hypervisor firewall, which this repository documents but
cannot apply from inside the guest, and an audit that verifies the firewall by
behaviour because the rules live where the guest cannot read them.

[docs/threat-model.md](docs/threat-model.md) states what each layer grants, and
which stronger options were rejected and why.

## This is not proven software

These projects are in early development. Nothing in them has been through
outside review, an external audit, or adversarial testing by anyone other than
the people who wrote them. Where a design argument is stated it is one person's
reasoning; where a test asserts something it asserts what that person thought
to check.

Treat every security property described in any of these repositories as a claim
awaiting scrutiny rather than one that has survived it, and do not deploy them
where being wrong would matter.

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

https://github.com/dejima-org/dejima/blob/main/SECURITY.md
