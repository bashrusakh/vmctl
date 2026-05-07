<div align="center">

# vmctl

Простое, безопасное и надёжное управление виртуальными машинами на standalone ESXi

![Version](https://img.shields.io/badge/version-0.1.0-blue?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.8%2B-blue?style=flat-square)
![ESXi](https://img.shields.io/badge/ESXi-7.0%20Enterprise-brightgreen?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

</div>

<br>

`hermes-vmctl` — современный CLI-инструмент для создания, управления и жизненного цикла виртуальных машин на standalone ESXi без vCenter.

## Основные возможности

- Полностью standalone (работает без vCenter)
- Template-based provisioning с cloud-init
- Поддержка нескольких datastores с контролем размещения
- Жёсткие квоты и защита важных ВМ (`protected_vms`)
- Полный lifecycle: `create → status → delete → purge + recover`
- Безопасная модель: forced-command SSH helper + минимальные права
- Удобная диагностика: `preflight + doctor`

---

## Быстрый старт

```bash
# Скачать и установить
curl -L https://github.com/bashrusakh/vmctl/releases/download/v0.1.0/hermes-vmctl-v0.1.0.tar.gz -o hermes-vmctl.tar.gz

tar -xzf hermes-vmctl.tar.gz
cd hermes-vmctl

cp install.env.example install.env
nano install.env

sudo scripts/install-full-stack.sh --env ./install.env

vmctl preflight
vmctl doctor
```

### Пример создания ВМ

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

## Основные команды

- `create` — создать новую ВМ
- `status <name>` — показать статус ВМ
- `list [--all]` — список ВМ
- `delete <name> [--force]` — удалить ВМ
- `purge <deleted-name>` — окончательно удалить данные
- `recover [--apply]` — восстановить ВМ по маркерам
- `preflight` — проверка конфигурации
- `doctor` — полная диагностика системы

## Требования

- ESXi 7.0+ Enterprise (standalone)
- Linux-машина (Hermes) с Python 3.8+
- SSH-доступ от Hermes к ESXi

## Безопасность

- Direct-режим отключён по умолчанию
- Forced-command SSH helper с whitelist-командами
- Строгая валидация путей и имён
- Поддержка списка защищённых ВМ (`protected_vms`)

## Документация

- [Инструкция по установке](./README.bootstrap.md)
- [Список исправлений](./docs/BUGFIX_LIST_TEST_PHASE.md)
- [История изменений](./CHANGELOG.md)

---

Made with ❤️ for clean and secure ESXi infrastructure
