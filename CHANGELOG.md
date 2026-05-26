# Changelog

## Unreleased

### Fixed
- Clarified `skills/devops/vmctl-ops` execution contract for hardened installs: authoritative validation must run in the installer-managed `vmctl-runner` context, not by executing `/opt/hermes-vmctl/bin/vmctl` directly as the interactive user.
- Updated `skills/devops/vmctl-ops/SKILL.md` health-gate examples to use:
  - `sudo -u vmctl-runner -H /opt/hermes-vmctl/bin/vmctl mode`
  - `sudo -u vmctl-runner -H /opt/hermes-vmctl/bin/vmctl preflight`
  - `sudo -u vmctl-runner -H /opt/hermes-vmctl/bin/vmctl doctor`
  - `sudo -u vmctl-runner -H /opt/hermes-vmctl/bin/vmctl list --all`
- Updated `skills/devops/vmctl-ops/README.md` to describe the hardened-install runner model and remove misleading guidance that implied plain interactive-user `vmctl` execution was authoritative.

## v0.1.5 - 2026-05-13

### Added
- Template-level hot-add controls in `config/vmctl.yaml`:
  - `templates.<name>.cpu_hot_add` (boolean, default `true`)
  - `templates.<name>.memory_hot_add` (boolean, default `true`)

### Changed
- VMX rendering now enforces hot-add flags from template config in both VMX generation paths:
  - template-VMX sanitize path
  - minimal VMX fallback path
- `vcpu.hotadd` and `mem.hotadd` are now explicitly set from template config instead of being always-on constants.

### Verified
- End-to-end `vmctl create` smoke test passed after the change (`status: ready`), confirming provisioning remains stable with configurable hot-add behavior.

## v0.1.4 - 2026-05-12

### Fixed
- ESXi bootstrap datastore permission assignment now correctly resolves datastore entities from `vim-cmd hostsvc/datastore/listsummary` when ESXi returns UUID-style IDs (`vim.Datastore:<uuid>`), not only legacy `datastore-XX` IDs.
- `vmctl create` govc auth path now normalizes split credentials (`GOVC_USERNAME`/`GOVC_PASSWORD`) into URL userinfo when needed, preventing `govc datastore.download` failures with `open <user>: permission denied` on affected govc builds.
- `vmctl create` now fails fast on insecure or missing private SSH key files used for readiness checks, with explicit remediation (`chmod 600 ...`) instead of a late generic SSH readiness failure.

### Changed
- Runtime govc invocation now applies auth normalization consistently before every govc call.

## v0.1.3 - 2026-05-12

### Added
- New `vmctl sync-check` command to explicitly validate config sync between installer source (`/opt/hermes-vmctl/install.env`) and runtime config (`/opt/hermes-vmctl/config/vmctl.yaml`).

### Changed
- `vmctl create` now performs a strict install-env drift check before helper operations and fails fast with an actionable remediation hint.
- `vmctl preflight` now includes strict `config_drift_install_env` validation.
- `vmctl doctor` now includes strict `config_drift_install_env` validation.

### Fixed
- `install.env` parsing in runtime drift checks now supports multiline quoted values (required for `VMCTL_TEMPLATES_JSON`).

### Notes
- This release prevents silent config/helper drift (for example, mismatched source datastore allowlists) from reaching VM create execution.

## v0.1.2 - 2026-05-12

### Fixed
- Installer now handles `ESXI_HOST` values provided as hostnames on systems where `ip route get <hostname>` fails: it resolves hostname to IPv4 and retries route-source detection.
- ESXi bootstrap SSH/SCP calls now use `StrictHostKeyChecking=accept-new` to avoid interactive host-key confirmation hangs during first connection.
- ESXi-side bootstrap privilege detection no longer relies only on `id`/`USER`; it now probes effective privileges and logs the reason when root-equivalent access is detected.

### Notes
- These changes harden canonical installation/bootstrap reliability on real-world ESXi environments without changing vmctl lifecycle command semantics.

## v0.1.1 - 2026-05-08

### Changed
- Renamed skill from `vmctl-post-install-ops` to `vmctl-ops`.
- Added publication-focused skill README at `skills/devops/vmctl-ops/README.md`.
- Standardized project docs and skill docs to English-only content.
- Updated release links to `v0.1.1` archive.

### Notes
- This release is documentation + skill packaging refresh; core vmctl runtime behavior is unchanged.

### v0.1.0 - 2026-05-07 (Post-RC fixes)

Technical hardening
- Fixed potential UnboundLocalError in temporary file cleanup (both template download and VMX upload).
- Quota lock now properly held until pending state is written (race condition eliminated).
- delete operation is now quota-independent.
- VMX sanitizer improved value parsing and banned prefix list.
- Preflight now performs runtime existence checks for templates when possible.
- Doctor emits clearer warnings for direct mode configuration.
- Minor cleanups and improved error messages.

## v0.1.0-rc1 - 2026-05-07

### Added
- Standalone ESXi 7 Enterprise support without vCenter.
- Hermes-side bootstrap with `vmctl-runner`.
- ESXi-side bootstrap with `vmctl-api` and `vmctl-ssh`.
- Forced-command ESXi helper backend.
- Multi-datastore config model.
- Template-based VM create from powered-off VM directory on datastore.
- cloud-init provisioning via VMware GuestInfo.
- E2E lifecycle: create, status, list, delete, purge.
- Recover from `guestinfo.vmctl.*` markers.
- Strict preflight and doctor checks.
- Release archive hygiene checks.

### Security
- Hermes user cannot read vmctl secrets.
- Production ESXi operations go through helper whitelist.
- Direct ESXi backend disabled by default.
- Path validation for VM/delete/purge flows.
- Protected VM names.
- No static MAC pool; MAC is generated by ESXi.
- No plaintext guest passwords in userdata.

### Fixed during integration testing
- `govc about` replaced by `govc version` for health checks.
- VMX upload moved to `govc datastore.upload`.
- IPv4-only `govc vm.ip -v4`.
- cloud-init readiness requires marker and SSH login.
- ESXi account password sync in bootstrap.
- Quoted heredoc helper generation.
- Recover inventory parsing and marker-based restoration.
- UUID validation clarified: ESXi-generated UUIDs are allowed, inherited template UUIDs are not.

### Post-gate fixes (code review)
- `render_metadata` signature cleaned for DHCP-only v1; removed unused static-IP args.
- Temporary file cleanup hardened (`local_tpl` initialized safely before `finally`).
- Quota race fixed: `quota.lock` is held through pending-state creation.
- `delete` no longer checks `max_vms_total` (delete is quota-independent).
- VMX sanitizer value handling cleaned (`key, value = split('=', 1)` preserving value format).
- Recover inventory parser now emits diagnostics for unparsed `getallvms` lines.
- `doctor` warns when direct mode is effective and when config allows break-glass direct mode.
- Preflight template checks strengthened (path prefix + VMX/disk existence checks).

### Known limitations
- No vCenter.
- No OVF/OVA import.
- No snapshot-chain templates.
- Static IP disabled in v1.
- MAC generated by ESXi.
