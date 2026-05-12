<div align="center">

# vmctl

Simple, safe, and reliable virtual machine management for standalone ESXi

![Version](https://img.shields.io/badge/version-0.1.1-blue?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.8%2B-blue?style=flat-square)
![ESXi](https://img.shields.io/badge/ESXi-7.0%20Enterprise-brightgreen?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

</div>

<br>

`vmctl` is a modern CLI tool for creating, managing, and operating virtual machines on standalone ESXi without vCenter.

## Key Features

- Fully standalone (works without vCenter)
- Template-based provisioning with cloud-init
- Multi-datastore support with placement control
- Strict quotas and protection for critical VMs (`protected_vms`)
- Full lifecycle: `create → status → delete → purge + recover`
- Secure model: forced-command SSH helper with minimal privileges
- Built-in diagnostics: `preflight + doctor`

---

## Quick Start

```bash
# Download and install
curl -L https://github.com/bashrusakh/vmctl/releases/latest/download/hermes-vmctl-v0.1.4.tar.gz -o hermes-vmctl.tar.gz

tar -xzf hermes-vmctl.tar.gz
cd hermes-vmctl

cp install.env.example install.env
nano install.env

sudo scripts/install-full-stack.sh --env ./install.env

vmctl preflight
vmctl doctor
```

### VM Creation Example

```bash
vmctl create \
  --name web-prod-01 \
  --template alma10 \
  --cpu 4 \
  --ram-mb 8192 \
  --disk-gb 80 \
  --network "VM Network" \
  --user admin \
  --ssh-key-file ~/.ssh/id_ed25519.pub \
  --ip dhcp
```

## Core Commands

- `create` — create a new VM
- `status <name>` — show VM status
- `list [--all]` — list VMs
- `delete <name> [--force]` — delete a VM
- `purge <deleted-name>` — permanently remove deleted VM data
- `recover [--apply]` — recover VM state from markers
- `preflight` — run configuration checks
- `doctor` — run full system diagnostics

## Requirements

- ESXi 7.0+ Enterprise (standalone)
- Linux host (Hermes) with Python 3.8+
- SSH access from Hermes to ESXi

## Security

- Direct mode is disabled by default
- Forced-command SSH helper with whitelisted commands
- Strict path and name validation
- Protected VM list support (`protected_vms`)

## Documentation

- [Installation Guide](./README.bootstrap.md)
- [Bugfix List](./docs/BUGFIX_LIST_TEST_PHASE.md)
- [Changelog](./CHANGELOG.md)

---

Made with ❤️ for clean and secure ESXi infrastructure
