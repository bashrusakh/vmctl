# vmctl — Bugfix List (Test Phase)

Период: с момента начала интеграционного тестирования проекта на реальном ESXi контуре.

## 1) Health/diagnostics

- **Исправлен govc-чек в preflight/doctor**:
  - было: `govc about` (нестабильно/несовместимо в контуре)
  - стало: `govc version`
- **Усилен резолв govc-бинаря**:
  - `GOVC_BIN` -> `shutil.which('govc')` -> `/usr/local/bin/govc`
- **Добавлен строгий helper-check** в doctor:
  - успех только при `rc == 0` и `stdout == "OK"`
- **Добавлен предупреждающий check** `cloudinit_vmware_datasource_hint`:
  - детектирует managed VM с IP, но без `guestinfo.vmctl.cloudinit_status=ready`
  - даёт явный remediation для VMware datasource в template.

## 2) ESXi bootstrap / helper reliability

- **bootstrap-esxi-side.sh**:
  - расширен `PATH` для non-interactive shell (`/bin:/sbin:/usr/bin:/usr/sbin`)
  - root-check сделан устойчивее
- **Идемпотентная синхронизация аккаунтов ESXi**:
  - если пользователь уже есть, теперь выполняется `esxcli system account set` для синхронизации пароля
  - устранён рассинхрон `esxi.env` vs фактические креды ESXi
- **helper heredoc переведён на quoted** `<<'HELPER_EOF'` + placeholders
- **authorized_keys append** переведён на безопасный `grep -qF`.

## 3) Create-flow (критические исправления)

- **Убран зависимый helper-путь `write-vmx-b64`** из критической цепочки
  - причина: на ESXi фиксировалось `base64: not found`
  - замена: генерация VMX локально + `govc datastore.upload`
- **Исправлен guest OS для alma10**:
  - корректный `guest_os: rhel9-64`
- **Добавлены/исправлены VMX-флаги совместимости**:
  - `vhv.enable = TRUE`
  - `vvtd.enable = TRUE`
  - `vcpu.hotadd = TRUE`
  - `mem.hotadd = TRUE`
  - `floppy0.present = FALSE`
  - корректный PCIe bridge layout
- **Исправлен режим firmware/NIC для template-based create**:
  - `firmware = efi`
  - `ethernet0.addressType = generated` (MAC от ESXi)
- **DHCP-путь стандартизирован для template-based provisioning**
- **Ожидание IP переведено на IPv4-only**:
  - `govc vm.ip -wait=... -v4`
  - чтобы не принимать link-local IPv6 за успех.

## 4) Cloud-init / SSH readiness

- **Переопределён критерий успешного create-теста**:
  - недостаточно `powered on + ip`
  - обязательно:
    1. IPv4 получен
    2. marker `guestinfo.vmctl.cloudinit_status=ready`
    3. SSH login по инжектированному ключу
- **Подтверждён root-cause SSH-fail** на тестовом этапе:
  - отсутствовал/не был включён VMware datasource в template
- После включения datasource в template:
  - marker `ready` появляется
  - SSH по ключу проходит стабильно.

## 5) Multi-datastore logic hardening

- Добавлен `--datastore` в create
- Fallback на `esxi.default_datastore`, если флаг не задан
- Валидация `config.datastores` + placement через `template.allowed_datastores`
- В state сохраняются:
  - `template_datastore`
  - `target_datastore`
  - `datastore` как alias
- delete/purge берут datastore **только из state/tombstone**, не из CLI.

## 6) Install/ops hardening

- В install-flow добавлен sanity-check PyYAML: `python3 -c "import yaml"`
- Bootstrap-параметры на ESXi передаются через временный env-файл (`/tmp/vmctl-bootstrap.env`), не inline с чувствительными значениями
- Ужесточены права:
  - `/opt/hermes-vmctl` = `750`
  - `/opt/hermes-vmctl/secrets` = `700`
  - файлы секретов = `600`
- `DRY_RUN` унифицирован через `${DRY_RUN:-0}`
- Добавлен install-лог: `/var/log/hermes-vmctl-install.log`
- `ALLOW_DIRECT_ESXI=0` оставлен как безопасный дефолт.

## 7) Bug patterns, подтверждённые в тестах (и закрытые)

- `govc about` false-red / incompatibility -> закрыто переходом на `govc version`
- helper `write-vmx-b64` падал из-за отсутствия `base64` -> закрыто upload-путём
- `Cannot complete login due to incorrect user/password` -> закрыто account-set sync в bootstrap
- `unsupportedGuestOS` -> закрыто `rhel9-64`
- `No PCIe slot available for SCSI0/Ethernet0` -> закрыто корректировкой VMX layout
- DHCP false-hang на IPv6 -> закрыто IPv4-only wait + сетевой проверкой nested
- `Permission denied` по SSH при наличии guestinfo -> закрыто включением VMware datasource в template.

## 8) Validation status after fixes

- `preflight`: green
- `doctor`: green + datasource hint check
- E2E cycle проходит:
  - create -> marker ready -> SSH -> sudo/install check -> delete -> purge
- Проверено, что на созданной VM возможны:
  - вход по ключу без пароля
  - `sudo -n`
  - установка пакетов (`dnf install ...`).

## 9) Remaining recommendations (not blocker)

- Автоматизировать VMware datasource в пайплайне сборки template (Packer/Ansible), чтобы не править вручную каждый новый образ.
- При желании разделить `doctor` на strict и advisory секции (сейчас hint не валит общий `ok`).
