# vmctl-post-install-ops

`vmctl-post-install-ops` is a post-install operational skill for Hermes Agent.

It tells the agent exactly what to do **after `vmctl` is already installed**:
- run mandatory health checks,
- execute a safe smoke VM lifecycle test,
- clean up test artifacts correctly,
- recover state drift if needed,
- report concise operator-ready status.

---

## Why this skill exists

Without a dedicated post-install playbook, agents tend to:
- skip prerequisite checks,
- improvise risky commands,
- leave stale test VMs/state behind,
- misuse `purge` by VM name instead of deleted tombstone name.

This skill standardizes a deterministic, safe flow for immediate validation of a `vmctl` environment.

---

## Scope

### In scope
- `vmctl mode`
- `vmctl preflight`
- `vmctl doctor`
- `vmctl list --all`
- smoke `create` / `status`
- cleanup `delete --force` + `purge <deleted_name>`
- `recover --dry-run` / `recover --apply`

### Out of scope
- Installing `vmctl` itself (bootstrap)
- Host account/role management on ESXi
- Production provisioning with non-test VM names

If `vmctl` is missing, the skill requires the agent to stop and redirect operator to install docs.

---

## Safety model

- **No privilege escalation guidance** in skill commands.
- Uses plain `vmctl ...` command style.
- Enforces test-only naming (`vmctl-test-*`).
- Requires cleanup unless operator explicitly asks to keep test VM.

---

## Typical workflow

1. Health gate (`mode`, `preflight`, `doctor`, `list --all`)
2. Smoke create/status on a test VM
3. Delete and purge test resources
4. Optional recover pass for residual drift
5. Structured short status report

---

## Prerequisites

- `vmctl` already installed and callable in PATH
- vmctl config/secrets already deployed
- ESXi/helper credentials already configured
- Access to `/opt/hermes-vmctl` state directory (for tombstone lookup)

---

## Installation source (for operators)

- Repository: https://github.com/bashrusakh/vmctl
- Release archive: https://github.com/bashrusakh/vmctl/releases/download/v0.1.0/hermes-vmctl-v0.1.0.tar.gz

---

## Install this skill in Hermes

```bash
hermes skills install https://raw.githubusercontent.com/bashrusakh/vmctl/main/skills/devops/vmctl-post-install-ops/SKILL.md
```

Optional: install with confirmation bypass in non-interactive flow:

```bash
hermes skills install https://raw.githubusercontent.com/bashrusakh/vmctl/main/skills/devops/vmctl-post-install-ops/SKILL.md --yes
```

---

## Use in session

- Load explicitly: `/skill vmctl-post-install-ops`
- Or ask naturally: “прогони post-install smoke для vmctl”

The skill’s execution contract and exact commands are defined in `SKILL.md`.

---

## Files

- `SKILL.md` — executable skill instructions for Hermes Agent
- `README.md` — human-facing publication overview (this file)
