# vmctl — Bugfix List (Test Phase)

Period: from the start of integration testing on the real ESXi environment.

## 1) Health/diagnostics

- **Fixed govc check in preflight/doctor**:
  - before: `govc about` (unstable/incompatible in this environment)
  - after: `govc version`
- **Hardened govc binary resolution**:
  - `GOVC_BIN` -> `shutil.which('govc')` -> `/usr/local/bin/govc`
- **Added strict helper check** in doctor:
  - success only when `rc == 0` and `stdout == "OK"`
- **Added warning check** `cloudinit_vmware_datasource_hint`:
  - detects managed VM with IP but without `guestinfo.vmctl.cloudinit_status=ready`
  - provides explicit remediation for VMware datasource in the template.

## 2) ESXi bootstrap / helper reliability

- **bootstrap-esxi-side.sh**:
  - expanded `PATH` for non-interactive shell (`/bin:/sbin:/usr/bin:/usr/sbin`)
  - made root-check more robust
- **Idempotent ESXi account synchronization**:
  - if user already exists, now runs `esxcli system account set` to sync password
  - removed drift between `esxi.env` and actual ESXi credentials
- **Helper heredoc switched to quoted** `<<'HELPER_EOF'` + placeholders
- **authorized_keys append** moved to safe `grep -qF` logic.

## 3) Create flow (critical fixes)

- **Removed helper-dependent path `write-vmx-b64`** from critical chain
  - reason: ESXi reported `base64: not found`
  - replacement: generate VMX locally + upload via `govc datastore.upload`
- **Fixed guest OS for alma10**:
  - correct `guest_os: rhel9-64`
- **Added/fixed VMX compatibility flags**:
  - `vhv.enable = TRUE`
  - `vvtd.enable = TRUE`
  - `vcpu.hotadd = TRUE`
  - `mem.hotadd = TRUE`
  - `floppy0.present = FALSE`
  - correct PCIe bridge layout
- **Fixed firmware/NIC mode for template-based create**:
  - `firmware = efi`
  - `ethernet0.addressType = generated` (MAC assigned by ESXi)
- **Standardized DHCP path for template-based provisioning**
- **Changed IP wait to IPv4-only**:
  - `govc vm.ip -wait=... -v4`
  - avoids treating link-local IPv6 as success.

## 4) Cloud-init / SSH readiness

- **Redefined successful create-test criteria**:
  - `powered on + ip` is not enough
  - required:
    1. IPv4 acquired
    2. marker `guestinfo.vmctl.cloudinit_status=ready`
    3. SSH login with injected key
- **Confirmed root cause of SSH failures** during test phase:
  - VMware datasource was missing/not enabled in template
- After enabling datasource in template:
  - `ready` marker appears
  - key-based SSH works consistently.

## 5) Multi-datastore logic hardening

- Added `--datastore` to create
- Fallback to `esxi.default_datastore` when flag is not provided
- Validation for `config.datastores` + placement via `template.allowed_datastores`
- State now stores:
  - `template_datastore`
  - `target_datastore`
  - `datastore` as alias
- delete/purge read datastore **only from state/tombstone**, not from CLI.

## 6) Install/ops hardening

- Added PyYAML sanity-check in install flow: `python3 -c "import yaml"`
- ESXi bootstrap parameters are passed through temporary env file (`/tmp/vmctl-bootstrap.env`), not inline with sensitive values
- Tightened permissions:
  - `/opt/hermes-vmctl` = `750`
  - `/opt/hermes-vmctl/secrets` = `700`
  - secret files = `600`
- Standardized `DRY_RUN` via `${DRY_RUN:-0}`
- Added install log: `/var/log/hermes-vmctl-install.log`
- `ALLOW_DIRECT_ESXI=0` kept as secure default.

## 7) Bug patterns confirmed in tests (and resolved)

- `govc about` false-red / incompatibility -> resolved by switching to `govc version`
- helper `write-vmx-b64` failed due to missing `base64` -> resolved via upload path
- `Cannot complete login due to incorrect user/password` -> resolved via account-set sync in bootstrap
- `unsupportedGuestOS` -> resolved with `rhel9-64`
- `No PCIe slot available for SCSI0/Ethernet0` -> resolved by VMX layout correction
- DHCP false-hang on IPv6 -> resolved by IPv4-only wait + nested network check
- SSH `Permission denied` despite guestinfo marker -> resolved by enabling VMware datasource in template.

## 8) Validation status after fixes

- `preflight`: green
- `doctor`: green + datasource hint check
- E2E cycle passes:
  - create -> marker ready -> SSH -> sudo/install check -> delete -> purge
- Verified on created VM:
  - key-based passwordless login
  - `sudo -n`
  - package installation (`dnf install ...`).

## 9) Remaining recommendations (not blockers)

- Automate VMware datasource in template build pipeline (Packer/Ansible) to avoid manual edits for each new image.
- Optionally split `doctor` into strict and advisory sections (currently the hint does not fail overall `ok`).
