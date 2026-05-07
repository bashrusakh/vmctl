#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="install.env"
DRY_RUN_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --env)
      ENV_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN_ARG="1"
      shift
      ;;
    -h|--help)
      echo "Usage: sudo $0 --env ./install.env [--dry-run]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/load-env.sh
source "$SCRIPT_DIR/lib/load-env.sh"

load_env_file "$ENV_FILE"
if [ -n "$DRY_RUN_ARG" ]; then
  DRY_RUN="1"
fi
validate_env_common
detect_hermes_ip

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[install-full-stack] $*"; }

[ "$(id -u)" = "0" ] || die "Run as root on Hermes VM"

LOG_FILE="/var/log/hermes-vmctl-install.log"
if touch "$LOG_FILE" 2>/dev/null; then
  chmod 600 "$LOG_FILE" || true
  if [ -n "${BASH_VERSION:-}" ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    exec >>"$LOG_FILE" 2>&1
  fi
fi

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

run_sh() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] $*"
  else
    bash -c "$*"
  fi
}

rand_pass() {
  # ESXi account passwords must be reasonably short; target 16 chars from safe set.
  openssl rand -base64 18 | tr -dc 'A-Za-z0-9@#%+=:._-' | head -c 16
}

find_govc_bin() {
  if command -v govc >/dev/null 2>&1; then
    command -v govc
    return 0
  fi
  [ -x /usr/local/bin/govc ] && { echo /usr/local/bin/govc; return 0; }
  [ -x /usr/bin/govc ] && { echo /usr/bin/govc; return 0; }
  return 1
}

install_packages() {
  log "Installing local dependencies"

  if command -v dnf >/dev/null 2>&1; then
    run dnf install -y python3 python3-pip jq openssh-clients sshpass tar gzip curl rsync openssl
  elif command -v apt-get >/dev/null 2>&1; then
    run apt-get update
    run apt-get install -y python3 python3-pip jq openssh-client sshpass tar gzip curl rsync openssl
  else
    die "Unsupported distro: no dnf or apt-get"
  fi

  run_sh "python3 -m pip install --user pyyaml || python3 -m pip install pyyaml"
  run_sh "python3 -c 'import yaml'"
}

install_govc() {
  log "Checking govc"

  if command -v govc >/dev/null 2>&1; then
    govc version || true
    return 0
  fi

  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) govc_arch="x86_64" ;;
    aarch64|arm64) govc_arch="arm64" ;;
    *) die "Unsupported arch for govc auto-install: $arch" ;;
  esac

  os="$(uname -s)"
  [ "$os" = "Linux" ] || die "Only Linux Hermes VM supported by this installer"

  tmp="/tmp/govc.tar.gz"
  url="https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_${govc_arch}.tar.gz"

  log "Downloading govc from $url"
  run curl -fsSL -o "$tmp" "$url"
  run tar -C /usr/local/bin -xzf "$tmp" govc
  run chmod +x /usr/local/bin/govc
  # sudo secure_path often excludes /usr/local/bin; install compatibility wrapper in /usr/bin.
  cat > /tmp/govc-wrapper.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "about" ]; then
  shift
  exec /usr/local/bin/govc version "$@"
fi
exec /usr/local/bin/govc "$@"
EOF
  run cp /tmp/govc-wrapper.sh /usr/bin/govc
  run chmod +x /usr/bin/govc
  if command -v govc >/dev/null 2>&1; then
    govc version || true
  fi
}

create_local_users() {
  log "Creating local group/user"

  getent group "$VMCTL_GROUP" >/dev/null || run groupadd --system "$VMCTL_GROUP"

  if ! id "$VMCTL_USER" >/dev/null 2>&1; then
    run useradd --system --create-home --home-dir "$APP_DIR" --shell /sbin/nologin --gid "$VMCTL_GROUP" "$VMCTL_USER"
  fi

  id "$HERMES_USER" >/dev/null 2>&1 || die "Hermes user does not exist: $HERMES_USER"

  run mkdir -p "$APP_DIR"/{bin,config,state/{pending,active,deleted,failed},locks/vm,templates,logs,secrets,tmp}
  run chown -R "$VMCTL_USER:$VMCTL_GROUP" "$APP_DIR"
  run chmod 750 "$APP_DIR"
  run chmod 750 "$APP_DIR/bin" "$APP_DIR/state" "$APP_DIR/logs"
  run chmod 700 "$APP_DIR/secrets"
}

generate_keys_and_passwords() {
  log "Generating SSH key and ESXi passwords"

  key="$APP_DIR/secrets/vmctl_ssh_key"

  regen_key=0
  if [ ! -f "$key" ]; then
    regen_key=1
  elif ssh-keygen -lf "$key" 2>/dev/null | grep -q 'ED25519'; then
    # ESXi host is in FIPS mode and rejects ed25519 keys.
    regen_key=1
  fi

  if [ "$regen_key" = "1" ]; then
    run rm -f "$key" "$key.pub"
    run sudo -u "$VMCTL_USER" ssh-keygen -t rsa -b 3072 -f "$key" -N "" -C "vmctl@$(hostname)"
  fi

  run chmod 600 "$key"
  run chmod 644 "$key.pub"

  if [ -z "${API_PASS:-}" ]; then
    API_PASS="$(rand_pass)"
  fi

  if [ -z "${SSH_PASS:-}" ]; then
    SSH_PASS="$(rand_pass)"
  fi

  cat > "$APP_DIR/secrets/generated-passwords.txt" <<EOF
API_USER=$API_USER
API_PASS=$API_PASS
SSH_USER=$SSH_USER
SSH_PASS=$SSH_PASS
EOF

  run chmod 600 "$APP_DIR/secrets/generated-passwords.txt"
  run chown "$VMCTL_USER:$VMCTL_GROUP" "$APP_DIR/secrets/generated-passwords.txt"
}

write_local_config() {
  log "Writing vmctl config and env"

  cat > "$APP_DIR/secrets/esxi.env" <<EOF
export ESXI_HOST='$ESXI_HOST'
export ESXI_USER='$SSH_USER'
export ESXI_SSH_PORT='22'
export ESXI_SSH_KEY='$APP_DIR/secrets/vmctl_ssh_key'

export GOVC_URL='https://$ESXI_HOST/sdk'
export GOVC_USERNAME='$API_USER'
export GOVC_PASSWORD='$API_PASS'
export GOVC_INSECURE=$GOVC_INSECURE
export GOVC_DATASTORE='$DEFAULT_DATASTORE'
export GOVC_NETWORK='$DEFAULT_NETWORK'
EOF

  chmod 600 "$APP_DIR/secrets/esxi.env"
  chown "$VMCTL_USER:$VMCTL_GROUP" "$APP_DIR/secrets/esxi.env"

  export APP_DIR DEFAULT_DATASTORE DATASTORES DEFAULT_NETWORK ALLOWED_NETWORKS VMCTL_TEMPLATES_JSON
  export MAX_CPU MAX_RAM_MB MAX_DISK_GB MAX_VMS_TOTAL MAX_VMS_PER_REQUEST
  export PROTECTED_VMS SSH_USER ESXI_HOST VM_DISK_FORMAT

  python3 - <<'PY' > "/tmp/vmctl.yaml.$$"
import json, os, yaml

def csv(name):
    return [x.strip() for x in os.environ.get(name, "").split(",") if x.strip()]

templates = json.loads(os.environ["VMCTL_TEMPLATES_JSON"])
datastores = {}
for ds in csv("DATASTORES"):
    datastores[ds] = {
        "path": f"/vmfs/volumes/{ds}",
        "deleted_dir": "_deleted",
        "templates_dir": "_templates",
    }

cfg = {
    "esxi": {
        "host": os.environ["ESXI_HOST"],
        "user": os.environ["SSH_USER"],
        "ssh_port": 22,
        "ssh_key": f"{os.environ['APP_DIR']}/secrets/vmctl_ssh_key",
        "default_datastore": os.environ["DEFAULT_DATASTORE"],
        "default_network": os.environ["DEFAULT_NETWORK"],
        "vm_disk_format": os.environ.get("VM_DISK_FORMAT", "thin"),
    },
    "datastores": datastores,
    "templates": templates,
    "allowed_networks": csv("ALLOWED_NETWORKS"),
    "limits": {
        "max_cpu": int(os.environ["MAX_CPU"]),
        "max_ram_mb": int(os.environ["MAX_RAM_MB"]),
        "max_disk_gb": int(os.environ["MAX_DISK_GB"]),
        "max_vms_total": int(os.environ["MAX_VMS_TOTAL"]),
        "max_vms_per_request": int(os.environ["MAX_VMS_PER_REQUEST"]),
    },
    "protected_vms": csv("PROTECTED_VMS"),
    "security": {
        "allow_direct_esxi": False,
    },
    "delete": {
        "deleted_dir": "_deleted",
    },
}

print(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))
PY

  mv "/tmp/vmctl.yaml.$$" "$APP_DIR/config/vmctl.yaml"
  chmod 640 "$APP_DIR/config/vmctl.yaml"
  chown "$VMCTL_USER:$VMCTL_GROUP" "$APP_DIR/config/vmctl.yaml"
}

install_sudoers() {
  log "Installing sudoers rule"

  sudoers="/etc/sudoers.d/hermes-vmctl"

  cat > "$sudoers" <<EOF
# Allow Hermes agent to run only vmctl as vmctl-runner.
$HERMES_USER ALL=($VMCTL_USER) NOPASSWD: $APP_DIR/bin/vmctl *
EOF

  chmod 440 "$sudoers"
  visudo -cf "$sudoers"
}

install_placeholder_vmctl() {
  if [ -x "$APP_DIR/bin/vmctl" ]; then
    log "vmctl already exists, skipping placeholder"
    return 0
  fi

  log "Installing placeholder vmctl"

  cat > "$APP_DIR/bin/vmctl" <<'EOF'
#!/usr/bin/env python3
import sys
print("vmctl placeholder installed. Replace with real vmctl implementation.")
print("args:", " ".join(sys.argv[1:]))
EOF

  chmod 750 "$APP_DIR/bin/vmctl"
  chown "$VMCTL_USER:$VMCTL_GROUP" "$APP_DIR/bin/vmctl"
}

build_esxi_ssh_cmd_prefix() {
  SSH_CMD_PREFIX=""
  SCP_CMD_PREFIX=""
  if [ -n "${ESXI_ROOT_SSH_KEY:-}" ]; then
    return 0
  fi
  if [ -n "${ESXI_ROOT_PASS:-}" ]; then
    command -v sshpass >/dev/null 2>&1 || die "sshpass is required when ESXI_ROOT_PASS is set"
    SSH_CMD_PREFIX="sshpass -p '$ESXI_ROOT_PASS'"
    SCP_CMD_PREFIX="sshpass -p '$ESXI_ROOT_PASS'"
  fi
}

prompt_esxi_root_pass_if_needed() {
  [ "${DRY_RUN:-0}" = "1" ] && return 0
  [ -n "${ESXI_ROOT_SSH_KEY:-}" ] && return 0
  [ -n "${ESXI_ROOT_PASS:-}" ] && return 0

  if [ -t 0 ]; then
    printf "Enter ESXi root password for one-time bootstrap: " >&2
    stty -echo
    IFS= read -r ESXI_ROOT_PASS
    stty echo
    printf "\n" >&2
    [ -n "$ESXI_ROOT_PASS" ] || die "Empty ESXI root password"
    export ESXI_ROOT_PASS
    trap 'unset ESXI_ROOT_PASS' EXIT
  else
    die "ESXI_ROOT_SSH_KEY is empty and no TTY for interactive password prompt. Set ESXI_ROOT_PASS in environment for this run only."
  fi
}

copy_and_run_esxi_bootstrap() {
  log "Running ESXi-side bootstrap"

  local pubkey
  if [ "${DRY_RUN:-0}" = "1" ]; then
    pubkey="DRY_RUN_PUBKEY_PLACEHOLDER"
  else
    pubkey="$(cat "$APP_DIR/secrets/vmctl_ssh_key.pub")"
  fi
  esxi_script="$SCRIPT_DIR/bootstrap-esxi-side.sh"
  [ -f "$esxi_script" ] || die "Missing $esxi_script"

  prompt_esxi_root_pass_if_needed
  build_esxi_ssh_cmd_prefix

  scp_opts=(-P "$ESXI_ROOT_PORT")
  ssh_opts=(-p "$ESXI_ROOT_PORT")
  if [ -n "${ESXI_ROOT_SSH_KEY:-}" ]; then
    scp_opts+=(-i "$ESXI_ROOT_SSH_KEY")
    ssh_opts+=(-i "$ESXI_ROOT_SSH_KEY")
  fi

  if [ -n "$SCP_CMD_PREFIX" ]; then
    run_sh "$SCP_CMD_PREFIX scp ${scp_opts[*]} '$esxi_script' '$ESXI_ROOT_USER@$ESXI_HOST:/tmp/bootstrap-esxi-side.sh'"
  else
    run scp "${scp_opts[@]}" "$esxi_script" "$ESXI_ROOT_USER@$ESXI_HOST:/tmp/bootstrap-esxi-side.sh"
  fi

  tmp_env_local="/tmp/vmctl-bootstrap.env.$$"
  cat > "$tmp_env_local" <<EOF
API_USER='$API_USER'
API_PASS='$API_PASS'
SSH_USER='$SSH_USER'
SSH_PASS='$SSH_PASS'
SSH_PUBKEY='$pubkey'
HERMES_IP='$HERMES_IP'
DATASTORES='$DATASTORES'
DEFAULT_DATASTORE='$DEFAULT_DATASTORE'
SSH_ROLE='$SSH_ROLE'
INSTALL_HELPER='$INSTALL_HELPER'
VM_DISK_FORMAT='$VM_DISK_FORMAT'
EOF

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] scp ${scp_opts[*]} $tmp_env_local $ESXI_ROOT_USER@$ESXI_HOST:/tmp/vmctl-bootstrap.env"
    echo "[DRY-RUN] ssh ${ssh_opts[*]} $ESXI_ROOT_USER@$ESXI_HOST \"set -a; . /tmp/vmctl-bootstrap.env; set +a; sh /tmp/bootstrap-esxi-side.sh\""
  else
    if [ -n "$SCP_CMD_PREFIX" ]; then
      run_sh "$SCP_CMD_PREFIX scp ${scp_opts[*]} '$tmp_env_local' '$ESXI_ROOT_USER@$ESXI_HOST:/tmp/vmctl-bootstrap.env'"
      run_sh "$SSH_CMD_PREFIX ssh ${ssh_opts[*]} '$ESXI_ROOT_USER@$ESXI_HOST' \"set -a; . /tmp/vmctl-bootstrap.env; set +a; sh /tmp/bootstrap-esxi-side.sh\""
      run_sh "$SSH_CMD_PREFIX ssh ${ssh_opts[*]} '$ESXI_ROOT_USER@$ESXI_HOST' 'rm -f /tmp/vmctl-bootstrap.env /tmp/bootstrap-esxi-side.sh'"
    else
      scp "${scp_opts[@]}" "$tmp_env_local" "$ESXI_ROOT_USER@$ESXI_HOST:/tmp/vmctl-bootstrap.env"
      ssh "${ssh_opts[@]}" "$ESXI_ROOT_USER@$ESXI_HOST" "set -a; . /tmp/vmctl-bootstrap.env; set +a; sh /tmp/bootstrap-esxi-side.sh"
      ssh "${ssh_opts[@]}" "$ESXI_ROOT_USER@$ESXI_HOST" "rm -f /tmp/vmctl-bootstrap.env /tmp/bootstrap-esxi-side.sh"
    fi
  fi
  rm -f "$tmp_env_local"
}

enforce_permissions() {
  log "Enforcing file permissions"
  run chown -R "$VMCTL_USER:$VMCTL_GROUP" "$APP_DIR"
  run chmod 750 "$APP_DIR"
  run chmod 750 "$APP_DIR/bin" "$APP_DIR/state" "$APP_DIR/logs"
  run chmod 700 "$APP_DIR/secrets"
  run chmod 600 "$APP_DIR/secrets/esxi.env"
  run chmod 600 "$APP_DIR/secrets/generated-passwords.txt"
  run chmod 600 "$APP_DIR/secrets/vmctl_ssh_key"
}

verify_access() {
  log "Verifying govc and SSH helper"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] verify govc/ssh"
    return 0
  fi

  GOVC_BIN="$(find_govc_bin || true)"
  [ -n "$GOVC_BIN" ] || die "govc binary not found"

  GOVC_URL="https://$ESXI_HOST/sdk"
  sudo -u "$VMCTL_USER" env -i \
    HOME="$APP_DIR" \
    PATH="/usr/local/bin:/usr/bin:/bin" \
    GOVC_URL="$GOVC_URL" \
    GOVC_USERNAME="$API_USER" \
    GOVC_PASSWORD="$API_PASS" \
    GOVC_INSECURE=1 \
    "$GOVC_BIN" version >/tmp/vmctl-govc-version.out 2>&1 || {
    cat /tmp/vmctl-govc-version.out >&2
    log "WARN: govc version failed (continuing to helper preflight check)"
  }

  if ! sudo -u "$VMCTL_USER" ssh \
    -i "$APP_DIR/secrets/vmctl_ssh_key" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$ESXI_HOST" preflight; then
    log "WARN: helper preflight via key failed (likely key not yet accepted / auth policy)."
  fi
}

main() {
  install_packages
  install_govc
  create_local_users
  generate_keys_and_passwords
  write_local_config
  install_sudoers
  install_placeholder_vmctl
  copy_and_run_esxi_bootstrap
  enforce_permissions
  verify_access

  cat <<EOF

DONE.

Hermes-side:
  app dir:       $APP_DIR
  runner user:   $VMCTL_USER
  hermes user:   $HERMES_USER
  sudoers:       /etc/sudoers.d/hermes-vmctl

ESXi-side:
  API user:      $API_USER
  SSH user:      $SSH_USER
  datastores:    $DATASTORES
  default ds:    $DEFAULT_DATASTORE
  network:       $DEFAULT_NETWORK

Secrets:
  $APP_DIR/secrets/esxi.env
  $APP_DIR/secrets/vmctl_ssh_key
  $APP_DIR/secrets/generated-passwords.txt

Config:
  $APP_DIR/config/vmctl.yaml

EOF
}

main "$@"
