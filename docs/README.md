# docs

| | |
| --- | --- |
| [building-a-devbox.md](building-a-devbox.md) | The guest-side runbook: install, bootstrap, verify, and what to keep off the machine |
| [threat-model.md](threat-model.md) | What each layer grants, why container escape is deprioritised, and which options were rejected |
| [reference.md](reference.md) | The three verdicts, the three addressing modes, and the one config key |
| [upgrading.md](upgrading.md) | Moving a devbox that already exists to a newer version, and why the two halves are counted separately |

The node-side half is [../proxmox/README.md](../proxmox/README.md), kept
separate so another hypervisor can be added without touching a guest-side step.
