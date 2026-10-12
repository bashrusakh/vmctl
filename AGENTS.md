<!-- generated-by: repo-docs-sync; file: AGENTS.md -->

# vmctl - AI Agent Reference

## Core Purpose
Project purpose: vmctl is a modern CLI tool for creating, managing, and operating virtual machines on standalone ESXi without vCenter.

Facts not found in the repository context:
- policy.version\_file: no version source-of-truth file documented
- policy.licenses: no license manifest or LICENSE file observed

## Architecture Overview
This render draws no architecture narrative of its own: the facts contract models component modules with their recorded paths and descriptions rather than a synthesized architecture summary, and no part outside the recorded facts is invented here. The recorded components, their paths, and their entry points are rendered under Repository Layout and Runtime Entry Points.

## Tech Stack
Technologies observed in the repository:
- **Python** (language) — evidence: `README.md`
- **ESXi** (platform) — evidence: `README.md`

## Repository Layout
Important paths observed in the repository:
- `.github/workflows/triage-backlog.yml` (GitHub Workflows)
- `.github/workflows/triage-issue.yml` (GitHub Workflows)
- `.github/workflows/triage-pr.yml` (GitHub Workflows)
- `docs` (Documentation Directory)
- `scripts` (Scripts Directory)

## Documentation Map
Repository documentation and the role of each file:
- `README.md` — project overview, usage, and quick‑start guide (evidence: `README.md`)
- `CONTRIBUTING.md` — contribution guidelines and triage label policy (evidence: `CONTRIBUTING.md`)
- `docs/BUGFIX_LIST_TEST_PHASE.md` — bug‑fix list documentation (evidence: `docs`)
- `scripts/install-full-stack.sh` — installation script (evidence: `scripts`)

## Build / Dev Commands
**create** — working directory `.`; evidence: `README.md`

```bash
vmctl create ...
```

**status** — working directory `.`; evidence: `README.md`

```bash
vmctl status <name>
```

**list** — working directory `.`; evidence: `README.md`

```bash
vmctl list [--all]
```

**delete** — working directory `.`; evidence: `README.md`

```bash
vmctl delete <name> [--force]
```

**purge** — working directory `.`; evidence: `README.md`

```bash
vmctl purge <deleted-name>
```

**recover** — working directory `.`; evidence: `README.md`

```bash
vmctl recover [--apply]
```

**preflight** — working directory `.`; evidence: `README.md`

```bash
vmctl preflight
```

**doctor** — working directory `.`; evidence: `README.md`

```bash
vmctl doctor
```

## Runtime Entry Points
Runtime entry points observed in the repository:
- **GitHub Workflows** — Automation workflows for triage of issues and pull requests (`.github/workflows/triage-backlog.yml`, `.github/workflows/triage-issue.yml`, `.github/workflows/triage-pr.yml`; evidence: `.github/workflows/triage-backlog.yml`)
- **Documentation Directory** — Contains project documentation files (`docs`; evidence: `docs`)
- **Scripts Directory** — Utility scripts for installation and configuration (`scripts`; evidence: `scripts`)

## Runtime Environments
Runtime environments: Not found in repository.

## Agent Constraints
Follow these strict rules when working in this repository:
- Read `AGENTS.md` / `agents.md` and `CONTRIBUTING.md` before commit/PR work.
- Do not guess. Check files before answering or changing behavior.
- Inspect the current repository state before editing.
- Check nearby implementation and tests before changing behavior.
- Reuse existing project style and architecture.
- Do not invent commands.
- Do not make unrelated refactors.
- Do not silently change behavior outside the task scope.
- Do not bypass tests or CI.
- Do not commit secrets.
- Do not introduce new dependencies, frameworks, tooling, generated files, or large artifacts unless the change explicitly requires it.
- Do not run git or GitHub write commands unless the user explicitly asks.
- Do not create, apply, rename, or remove labels unless the user explicitly asks; labels are contributor- and maintainer-owned. Follow the type-label convention in CONTRIBUTING.md.
- Only commit, open PRs, create issues, create tags, or create releases when explicitly asked by the user.

## Development Rules
Not recorded in the collected context.

## Documentation Maintenance
Project structure changes over time. AGENTS.md and CONTRIBUTING.md are guidance, not a replacement for checking the actual tree. If project structure, commands, architecture, test flow, contribution rules, release flow, or important entry points change, update the relevant Markdown file in the same PR. Keep docs useful and stable, and keep Markdown updates small. Do not duplicate the full file tree unless the project explicitly requires it. Describe stable conventions and important entry points, not every file.

## Testing Expectations
Not found in repository.
- Only use test commands found in repository evidence.
- If tests cannot run, report the exact command and exact error.

## PR / Review Expectations
Create focused changes and include test evidence when available; avoid direct pushes to protected branches.

Before PR work:
- Check git status.
- Review the full diff.
- Make sure only intended files are included.
- Make sure the branch is based on the repository's current default branch.
- Run the narrowest relevant tests/checks from repository evidence.
- If tests cannot run, report the exact command and exact error.
- Include summary, why/context, and validation/tests run.
- Include screenshots or manual verification steps for UI changes when relevant.
- Do not apply labels unless the user explicitly asks; follow the type-label convention in CONTRIBUTING.md.
- Do not mark work as ready if checks are unknown or failing.

## Issue Rules
- Only open an issue when the user explicitly asks.
- Verify the problem against the current code/state first.
- Search existing issues if possible.
- Describe facts only: actual behavior, expected behavior, reproduction steps, affected screen/API/module, and logs or screenshots when useful.
- Do not invent root cause; label a suspected root cause clearly as a hypothesis.
- Keep the issue actionable and specific.

## Release / Tag Rules
- Only create or update a tag/release when the user explicitly asks.
- Never treat a release as complete if the GitHub Release body is empty, placeholder, too thin, or unreviewed auto-generated-only notes.
- Open and read the created release before reporting completion.
- Compare the release notes with the previous release quality when a previous release exists.
- If GitHub Actions created a release without proper notes, update the release body before reporting completion.
- Do not invent changelog entries.
- Use commits, merged PRs, linked issues, tags, release history, and actual diffs only.
- Before marking release work as done, verify the GitHub Release page has the correct tag, title, body, and assets.
