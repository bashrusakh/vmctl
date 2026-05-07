---
name: vmctl-post-install-ops
description: Use when vmctl is already installed and the agent must immediately run safe post-install checks and first lifecycle actions without guessing.
version: 1.0.0
author: Leonid + Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [vmctl, esxi, post-install, validation, operations]
    related_skills: [esxi-standalone-vmctl-delivery]
---

# vmctl Post-Install Operations

## Overview
This skill defines what the agent should do **right after vmctl installation** on the Hermes host.

Goal: quickly verify that vmctl is operational, run a safe smoke cycle, clean artifacts, and report status in operator-friendly form.

## When to Use
- vmctl was just installed or reinstalled.
- ESXi/helper credentials are already configured.
- Operator asks: “прогони тест”, “проверь после установки”, “почему не работает”.

Do **not** use for:
- bootstrap installation itself;
- modifying ESXi host accounts/roles;
- production VM provisioning with non-test names.

## Default Execution Mode
- Run vmctl as service user:
  - `sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl ...`
- Workdir: `/opt/hermes-vmctl`
- Do not guess values; use config/secrets already deployed by installer.

## Phase 1 — Mandatory health gate
Run in order:

```bash
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl mode
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl preflight
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl doctor
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl list --all
```

Rules:
1. If `preflight` or `doctor` is red -> stop and report blocker.
2. If `list --all` shows pending/failed from old runs, recover/cleanup before new create-tests.

## Phase 2 — Safe smoke create test
Use a test name only:
- `vmctl-test-<purpose>-<timestamp>`

Minimal smoke command:

```bash
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl create \
  --name vmctl-test-smoke-<timestamp> \
  --template alma10 \
  --cpu 2 \
  --ram-mb 4096 \
  --disk-gb 40 \
  --user hermes \
  --ssh-key-file /tmp/vmctl_test_key.pub
```

Then:

```bash
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl status <name>
```

Success criteria:
- state is `ready`
- IPv4 exists
- no exception from create/status

## Phase 3 — Cleanup policy
Delete+purge test VM after smoke run unless operator asked to keep it.

```bash
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl delete <name> --force
```

Important: `purge` uses **deleted tombstone name**, not original VM name.

```bash
# discover tombstone
python3 - <<'PY'
import glob, os
vm='<name>'
paths=glob.glob('/opt/hermes-vmctl/state/deleted/*.json')
c=[p for p in paths if vm in os.path.basename(p)]
if c:
    c.sort(key=os.path.getmtime, reverse=True)
    print(os.path.basename(c[0])[:-5])
PY

sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl purge <deleted_name>
```

## Recovery flow (if state drift exists)
If ESXi has managed VM but state is missing:

```bash
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl recover --dry-run
sudo -n -u vmctl-runner /opt/hermes-vmctl/bin/vmctl recover --apply
```

Then run delete/purge again.

## Operator Output Format
Report concise facts:
- preflight: pass/fail
- doctor: pass/fail
- create: pass/fail + vm name
- cleanup: deleted + purged / blocked
- residual check: `recover --dry-run` actions count

## Common Pitfalls
1. Running vmctl as wrong user -> secrets permission errors.
2. Purging by original VM name -> `deleted tombstone not found`.
3. Reusing stale test names -> clone/file already exists errors.
4. Treating orphan datastore folders as vmctl-managed state.

## Verification Checklist
- [ ] `mode` confirms helper-only effective mode.
- [ ] `preflight` is green.
- [ ] `doctor` is green.
- [ ] smoke `create` reaches `ready`.
- [ ] test VM removed by `delete --force`.
- [ ] tombstone purged by deleted-name.
- [ ] `recover --dry-run` has no unexpected actions.
