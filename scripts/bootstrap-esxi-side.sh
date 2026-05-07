#!/bin/sh
set -eu
export PATH="/bin:/sbin:/usr/bin:/usr/sbin"

API_USER="${API_USER:-vmctl-api}"
API_PASS="${API_PASS:-}"

SSH_USER="${SSH_USER:-vmctl-ssh}"
SSH_PASS="${SSH_PASS:-}"
SSH_PUBKEY="${SSH_PUBKEY:-}"

HERMES_IP="${HERMES_IP:-}"
DATASTORES="${DATASTORES:-datastore1}"
DEFAULT_DATASTORE="${DEFAULT_DATASTORE:-datastore1}"

API_ROLE="${API_ROLE:-VMCTL_API}"
SSH_ROLE="${SSH_ROLE:-Admin}"
INSTALL_HELPER="${INSTALL_HELPER:-1}"

STORE_DIR="${STORE_DIR:-/store/vmctl}"
ACCESS_CONF="/etc/security/access.conf"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  echo "[bootstrap-esxi-side] $*"
}

is_root=0
if command -v id >/dev/null 2>&1; then
  [ "$(id -u)" = "0" ] && is_root=1
fi
if [ "$is_root" -ne 1 ] && [ "${USER:-}" = "root" ]; then
  is_root=1
fi
[ "$is_root" -eq 1 ] || die "Run on ESXi as root"

[ -n "$API_PASS" ] || die "API_PASS is required"
[ -n "$SSH_PASS" ] || die "SSH_PASS is required"
[ -n "$SSH_PUBKEY" ] || die "SSH_PUBKEY is required"
[ -n "$HERMES_IP" ] || die "HERMES_IP is required"
[ -n "$DATASTORES" ] || die "DATASTORES is required"
[ -n "$DEFAULT_DATASTORE" ] || die "DEFAULT_DATASTORE is required"

echo "$API_USER" | grep -Eq '^[A-Za-z][A-Za-z0-9._-]{0,31}$' || die "Invalid API_USER"
echo "$SSH_USER" | grep -Eq '^[A-Za-z][A-Za-z0-9._-]{0,31}$' || die "Invalid SSH_USER"
echo "$HERMES_IP" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || die "Invalid HERMES_IP"

case "$SSH_ROLE" in
  Admin|ReadOnly|NoAccess) ;;
  *) die "SSH_ROLE must be Admin, ReadOnly, or NoAccess" ;;
esac

validate_datastores() {
  OLDIFS="$IFS"
  IFS=','
  for ds in $DATASTORES; do
    ds="$(echo "$ds" | sed 's/^ *//;s/ *$//')"
    [ -n "$ds" ] || continue
    echo "$ds" | grep -Eq '^[A-Za-z0-9._-]+$' || die "Invalid datastore name: $ds"
    [ -d "/vmfs/volumes/$ds" ] || die "Datastore not found: /vmfs/volumes/$ds"
  done
  IFS="$OLDIFS"
}

account_exists() {
  id "$1" >/dev/null 2>&1 && return 0
  esxcli system account list 2>/dev/null | awk '{print $1}' | grep -Fxq "$1"
}

create_account() {
  user="$1"
  pass="$2"
  desc="$3"

  if account_exists "$user"; then
    log "User exists: $user (syncing password)"
    if ! esxcli system account set \
      --id="$user" \
      --password="$pass" \
      --password-confirmation="$pass" >/tmp/vmctl-account-set.out 2>&1; then
      cat /tmp/vmctl-account-set.out >&2
      die "Failed to sync password for user: $user"
    fi
    return 0
  fi

  log "Creating user: $user"
  if ! esxcli system account add \
    --id="$user" \
    --password="$pass" \
    --password-confirmation="$pass" \
    --description="$desc" >/tmp/vmctl-account-add.out 2>&1; then
    if grep -qi 'already exists' /tmp/vmctl-account-add.out; then
      log "User already exists (race-safe), syncing password: $user"
      if ! esxcli system account set \
        --id="$user" \
        --password="$pass" \
        --password-confirmation="$pass" >/tmp/vmctl-account-set.out 2>&1; then
        cat /tmp/vmctl-account-set.out >&2
        die "Failed to sync password for existing user: $user"
      fi
      return 0
    fi
    cat /tmp/vmctl-account-add.out >&2
    die "Failed to create user: $user"
  fi
}

role_exists() {
  vim-cmd vimsvc/auth/roles | grep -q "name = \"$1\""
}

create_api_role() {
  if role_exists "$API_ROLE"; then
    log "Role exists: $API_ROLE"
    return 0
  fi

  log "Creating API role: $API_ROLE"

  API_PRIVS="
System.Anonymous
System.Read
System.View
Datastore.Browse
Datastore.AllocateSpace
Datastore.FileManagement
Network.Assign
Resource.AssignVMToPool
VirtualMachine.Config.AddRemoveDevice
VirtualMachine.Config.AdvancedConfig
VirtualMachine.Config.Annotation
VirtualMachine.Config.CPUCount
VirtualMachine.Config.EditDevice
VirtualMachine.Config.Memory
VirtualMachine.Config.Settings
VirtualMachine.Config.ResetGuestInfo
VirtualMachine.Interact.AnswerQuestion
VirtualMachine.Interact.PowerOff
VirtualMachine.Interact.PowerOn
VirtualMachine.Inventory.Create
VirtualMachine.Inventory.CreateFromExisting
VirtualMachine.Inventory.Delete
VirtualMachine.Inventory.Register
VirtualMachine.Inventory.Unregister
"

  # shellcheck disable=SC2086
  vim-cmd vimsvc/auth/role_add "$API_ROLE" $API_PRIVS
}

add_permission() {
  entity="$1"
  principal="$2"
  role="$3"

  log "Adding permission: entity=$entity principal=$principal role=$role"

  vim-cmd vimsvc/auth/entity_permission_add "$entity" "$principal" false "$role" true >/tmp/vmctl-perm.out 2>&1 || {
    if grep -qi 'already' /tmp/vmctl-perm.out; then
      log "Permission already exists"
    else
      cat /tmp/vmctl-perm.out >&2
      die "Failed to add permission"
    fi
  }
}

allow_ssh_access_conf() {
  user="$1"

  log "Allowing SSH in access.conf for $user"

  if [ -f "$ACCESS_CONF" ]; then
    cp "$ACCESS_CONF" "$ACCESS_CONF.vmctl-backup-$(date -u +%Y%m%d%H%M%S)"
  fi

  if grep -Eq "^[+-]:$user:ALL" "$ACCESS_CONF"; then
    sed -i "s|^[+-]:$user:ALL|+:$user:ALL|" "$ACCESS_CONF"
  else
    if grep -q '^-:ALL:ALL' "$ACCESS_CONF"; then
      sed -i "/^-:ALL:ALL/i +:$user:ALL" "$ACCESS_CONF"
    else
      echo "+:$user:ALL" >> "$ACCESS_CONF"
    fi
  fi
}

install_helper() {
  [ "$INSTALL_HELPER" = "1" ] || return 0

  log "Installing forced-command helper"

  mkdir -p "$STORE_DIR"

  cat > "$STORE_DIR/esxi-helper.sh" <<'HELPER_EOF'
#!/bin/sh
set -eu
export PATH="/bin:/sbin:/usr/bin:/usr/sbin"

ALLOWED_DATASTORES="__ALLOWED_DATASTORES__"
DEFAULT_DATASTORE="__DEFAULT_DATASTORE__"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

trim() {
  echo "$1" | sed 's/^ *//;s/ *$//'
}

safe_ds() {
  ds="$(trim "$1")"
  echo "$ds" | grep -Eq '^[A-Za-z0-9._-]+$' || return 1
  OLDIFS="$IFS"
  IFS=','
  ok=0
  for allowed in $ALLOWED_DATASTORES; do
    allowed="$(trim "$allowed")"
    [ "$ds" = "$allowed" ] && ok=1
  done
  IFS="$OLDIFS"
  [ "$ok" = "1" ] || return 1
  [ -d "/vmfs/volumes/$ds" ] || return 1
  return 0
}

safe_name() {
  n="$1"
  echo "$n" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$' || return 1
  echo "$n" | grep -q '\\.\\.' && return 1
  return 0
}

safe_deleted_name() {
  n="$1"
  echo "$n" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,90}$' || return 1
  echo "$n" | grep -q '\\.\\.' && return 1
  return 0
}

safe_template_rel_dir() {
  p="$1"
  echo "$p" | grep -Eq '^_templates/[A-Za-z0-9._/-]{1,160}$' || return 1
  echo "$p" | grep -q '\\.\\.' && return 1
  echo "$p" | grep -q '//' && return 1
  return 0
}

safe_file() {
  f="$1"
  echo "$f" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$' || return 1
  echo "$f" | grep -q '\\.\\.' && return 1
  return 0
}

need_vmid() {
  echo "$1" | grep -Eq '^[0-9]+$' || die "invalid vmid"
}

ds_path() {
  ds="$1"
  echo "/vmfs/volumes/$ds"
}

cmdline="${SSH_ORIGINAL_COMMAND:-}"
[ -n "$cmdline" ] || die "no command"

# vmctl must not pass args containing whitespace to helper.
set -- $cmdline
cmd="${1:-}"
shift || true

case "$cmd" in
  preflight)
    OLDIFS="$IFS"
    IFS=','
    for ds in $ALLOWED_DATASTORES; do
      ds="$(trim "$ds")"
      safe_ds "$ds" || die "invalid datastore in allowlist: $ds"
      mkdir -p "/vmfs/volumes/$ds/_deleted"
    done
    IFS="$OLDIFS"
    which vmkfstools >/dev/null 2>&1 || die "vmkfstools not found"
    which vim-cmd >/dev/null 2>&1 || die "vim-cmd not found"
    echo "OK"
    ;;

  mkdir-vm)
    ds="${1:-}"
    vm="${2:-}"
    safe_ds "$ds" || die "unsafe datastore"
    safe_name "$vm" || die "unsafe vm name"
    mkdir -p "/vmfs/volumes/$ds/$vm"
    ;;

  clone-disk)
    src_ds="${1:-}"
    tpl_rel="${2:-}"
    tpl_disk="${3:-}"
    dst_ds="${4:-}"
    vm="${5:-}"
    disk_format="${6:-thin}"
    safe_ds "$src_ds" || die "unsafe source datastore"
    safe_ds "$dst_ds" || die "unsafe target datastore"
    safe_template_rel_dir "$tpl_rel" || die "unsafe template rel path"
    safe_file "$tpl_disk" || die "unsafe template disk"
    safe_name "$vm" || die "unsafe vm name"
    case "$disk_format" in
      thin|zeroedthick|eagerzeroedthick) ;;
      *) die "invalid disk format" ;;
    esac
    src="/vmfs/volumes/$src_ds/$tpl_rel/$tpl_disk"
    dst="/vmfs/volumes/$dst_ds/$vm/$vm.vmdk"
    [ -f "$src" ] || die "template disk not found: $src"
    [ -d "/vmfs/volumes/$dst_ds/$vm" ] || die "vm dir not found"
    vmkfstools -i "$src" "$dst" -d "$disk_format"
    ;;

  expand-disk)
    ds="${1:-}"
    vm="${2:-}"
    size_gb="${3:-}"
    safe_ds "$ds" || die "unsafe datastore"
    safe_name "$vm" || die "unsafe vm name"
    echo "$size_gb" | grep -Eq '^[0-9]{1,4}$' || die "unsafe disk size"
    [ -f "/vmfs/volumes/$ds/$vm/$vm.vmdk" ] || die "vm disk not found"
    vmkfstools -X "${size_gb}G" "/vmfs/volumes/$ds/$vm/$vm.vmdk"
    ;;

  write-vmx-b64)
    ds="${1:-}"
    vm="${2:-}"
    safe_ds "$ds" || die "unsafe datastore"
    safe_name "$vm" || die "unsafe vm name"
    [ -d "/vmfs/volumes/$ds/$vm" ] || die "vm dir not found"
    tmp="/tmp/vmctl-$vm.vmx.b64"
    out="/vmfs/volumes/$ds/$vm/$vm.vmx"
    cat > "$tmp"
    if command -v base64 >/dev/null 2>&1; then
      base64 -d "$tmp" > "$out"
    elif command -v openssl >/dev/null 2>&1; then
      openssl base64 -d -A -in "$tmp" -out "$out"
    else
      rm -f "$tmp"
      die "no base64 decoder available"
    fi
    rm -f "$tmp"
    ;;

  register)
    ds="${1:-}"
    vm="${2:-}"
    safe_ds "$ds" || die "unsafe datastore"
    safe_name "$vm" || die "unsafe vm name"
    [ -f "/vmfs/volumes/$ds/$vm/$vm.vmx" ] || die "vmx not found"
    vim-cmd solo/registervm "/vmfs/volumes/$ds/$vm/$vm.vmx"
    ;;

  unregister)
    vmid="${1:-}"
    need_vmid "$vmid"
    vim-cmd vmsvc/unregister "$vmid"
    ;;

  power-on)
    vmid="${1:-}"
    need_vmid "$vmid"
    vim-cmd vmsvc/power.on "$vmid"
    ;;

  power-off)
    vmid="${1:-}"
    need_vmid "$vmid"
    vim-cmd vmsvc/power.off "$vmid"
    ;;

  power-state)
    vmid="${1:-}"
    need_vmid "$vmid"
    vim-cmd vmsvc/power.getstate "$vmid"
    ;;

  getallvms)
    vim-cmd vmsvc/getallvms
    ;;

  soft-delete)
    ds="${1:-}"
    vm="${2:-}"
    deleted_name="${3:-}"
    safe_ds "$ds" || die "unsafe datastore"
    safe_name "$vm" || die "unsafe vm name"
    safe_deleted_name "$deleted_name" || die "unsafe deleted name"
    [ -d "/vmfs/volumes/$ds/$vm" ] || die "vm dir not found"
    mkdir -p "/vmfs/volumes/$ds/_deleted"
    mv "/vmfs/volumes/$ds/$vm" "/vmfs/volumes/$ds/_deleted/$deleted_name"
    ;;

  purge)
    ds="${1:-}"
    deleted_name="${2:-}"
    safe_ds "$ds" || die "unsafe datastore"
    safe_deleted_name "$deleted_name" || die "unsafe deleted name"
    [ -d "/vmfs/volumes/$ds/_deleted/$deleted_name" ] || die "deleted dir not found"
    rm -rf "/vmfs/volumes/$ds/_deleted/$deleted_name"
    ;;

  *)
    die "command not allowed: $cmd"
    ;;
esac
HELPER_EOF

  # Install-time substitution of placeholders (keep heredoc quoted above)
  esc_ds=$(printf '%s' "$DATASTORES" | sed 's/[\/&]/\\&/g')
  esc_default_ds=$(printf '%s' "$DEFAULT_DATASTORE" | sed 's/[\/&]/\\&/g')
  sed -i "s/__ALLOWED_DATASTORES__/$esc_ds/g" "$STORE_DIR/esxi-helper.sh"
  sed -i "s/__DEFAULT_DATASTORE__/$esc_default_ds/g" "$STORE_DIR/esxi-helper.sh"

  chmod 700 "$STORE_DIR/esxi-helper.sh"
}

install_authorized_key() {
  log "Installing SSH key for $SSH_USER"

  key_dir="/etc/ssh/keys-$SSH_USER"
  auth_file="$key_dir/authorized_keys"

  mkdir -p "$key_dir"
  touch "$auth_file"

  if [ "$INSTALL_HELPER" = "1" ]; then
    opts="from=\"$HERMES_IP\",no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty,command=\"/bin/sh $STORE_DIR/esxi-helper.sh\""
  else
    opts="from=\"$HERMES_IP\",no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty"
  fi

  if ! grep -qF "$SSH_PUBKEY" "$auth_file"; then
    echo "$opts $SSH_PUBKEY" >> "$auth_file"
  fi

  chmod 700 "$key_dir"
  chmod 600 "$auth_file"
  chown -R "$SSH_USER:users" "$key_dir" 2>/dev/null || true
}

main() {
  validate_datastores

  create_account "$API_USER" "$API_PASS" "vmctl API user"
  create_account "$SSH_USER" "$SSH_PASS" "vmctl SSH user"

  create_api_role

  add_permission "vim.Folder:ha-folder-root" "$API_USER" "$API_ROLE"
  add_permission "vim.ComputeResource:ha-compute-res" "$API_USER" "$API_ROLE"

  add_permission "vim.Folder:ha-folder-root" "$SSH_USER" "$SSH_ROLE"
  add_permission "vim.ComputeResource:ha-compute-res" "$SSH_USER" "$SSH_ROLE"

  allow_ssh_access_conf "$SSH_USER"
  install_helper
  install_authorized_key

  /etc/init.d/SSH restart || true

  OLDIFS="$IFS"
  IFS=','
  for ds in $DATASTORES; do
    ds="$(echo "$ds" | sed 's/^ *//;s/ *$//')"
    [ -n "$ds" ] || continue
    mkdir -p "/vmfs/volumes/$ds/_deleted"
  done
  IFS="$OLDIFS"

  cat <<EOF

DONE ESXi bootstrap.

API_USER=$API_USER
SSH_USER=$SSH_USER
DATASTORES=$DATASTORES
DEFAULT_DATASTORE=$DEFAULT_DATASTORE
HELPER=$STORE_DIR/esxi-helper.sh

Verify from Hermes:
  ssh -i /opt/hermes-vmctl/secrets/vmctl_ssh_key $SSH_USER@<ESXI_HOST> preflight

EOF
}

main "$@"
