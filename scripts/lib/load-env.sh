#!/usr/bin/env bash
set -euo pipefail

load_env_file() {
  local env_file="$1"

  if [ ! -f "$env_file" ]; then
    echo "ERROR: env file not found: $env_file" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a
}

require_var() {
  local name="$1"
  local value="${!name:-}"

  if [ -z "$value" ]; then
    echo "ERROR: required variable is empty: $name" >&2
    exit 1
  fi
}

default_var() {
  local name="$1"
  local default_value="$2"

  if [ -z "${!name:-}" ]; then
    export "$name=$default_value"
  fi
}

validate_csv_names() {
  local label="$1"
  local value="$2"
  IFS=',' read -ra items <<< "$value"
  for item in "${items[@]}"; do
    item="$(echo "$item" | sed 's/^ *//;s/ *$//')"
    [ -n "$item" ] || continue
    echo "$item" | grep -Eq '^[A-Za-z0-9._-]+$' || {
      echo "ERROR: invalid $label entry: $item" >&2
      exit 1
    }
  done
}

validate_env_common() {
  require_var ESXI_HOST
  require_var ESXI_ROOT_USER
  require_var ESXI_ROOT_PORT
  require_var DATASTORES
  require_var DEFAULT_DATASTORE
  require_var DEFAULT_NETWORK
  require_var ALLOWED_NETWORKS
  require_var VMCTL_TEMPLATES_JSON
  require_var HERMES_USER

  default_var APP_DIR "/opt/hermes-vmctl"
  default_var VMCTL_USER "vmctl-runner"
  default_var VMCTL_GROUP "vmctl"

  default_var API_USER "vmctl-api"
  default_var SSH_USER "vmctl-ssh"
  default_var SSH_ROLE "Admin"
  default_var INSTALL_HELPER "1"

  default_var MAX_CPU "8"
  default_var MAX_RAM_MB "32768"
  default_var MAX_DISK_GB "300"
  default_var MAX_VMS_TOTAL "20"
  default_var MAX_VMS_PER_REQUEST "1"

  default_var PROTECTED_VMS "hermes,router,dns,backup,vcenter,openclaw,moltis"
  default_var GOVC_INSECURE "1"
  default_var VM_DISK_FORMAT "thin"
  default_var DRY_RUN "0"

  case "$SSH_ROLE" in
    Admin|ReadOnly|NoAccess) ;;
    *)
      echo "ERROR: SSH_ROLE must be Admin, ReadOnly, or NoAccess. Got: $SSH_ROLE" >&2
      exit 1
      ;;
  esac

  case "$VM_DISK_FORMAT" in
    thin|zeroedthick|eagerzeroedthick) ;;
    *)
      echo "ERROR: VM_DISK_FORMAT must be one of: thin, zeroedthick, eagerzeroedthick" >&2
      exit 1
      ;;
  esac

  validate_csv_names "DATASTORES" "$DATASTORES"

  echo "$DEFAULT_DATASTORE" | grep -Eq '^[A-Za-z0-9._-]+$' || {
    echo "ERROR: invalid DEFAULT_DATASTORE: $DEFAULT_DATASTORE" >&2
    exit 1
  }

  case ",$DATASTORES," in
    *",$DEFAULT_DATASTORE,"*) ;;
    *)
      echo "ERROR: DEFAULT_DATASTORE must be listed in DATASTORES" >&2
      exit 1
      ;;
  esac

  python3 - <<'PY'
import json, os, sys
raw = os.environ.get("VMCTL_TEMPLATES_JSON", "")
try:
    data = json.loads(raw)
except Exception as e:
    print(f"ERROR: VMCTL_TEMPLATES_JSON is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict) or not data:
    print("ERROR: VMCTL_TEMPLATES_JSON must be a non-empty JSON object", file=sys.stderr)
    sys.exit(1)
required = {"datastore", "path", "vmx", "disk"}
allowed_ds = {x.strip() for x in os.environ["DATASTORES"].split(",") if x.strip()}
for name, item in data.items():
    if not isinstance(item, dict):
        print(f"ERROR: template {name!r} must be an object", file=sys.stderr)
        sys.exit(1)
    missing = required - set(item)
    if missing:
        print(f"ERROR: template {name!r} missing keys: {sorted(missing)}", file=sys.stderr)
        sys.exit(1)
    if item["datastore"] not in allowed_ds:
        print(f"ERROR: template {name!r} datastore {item['datastore']!r} is not in DATASTORES", file=sys.stderr)
        sys.exit(1)
    expected_prefix = f"/vmfs/volumes/{item['datastore']}/"
    if not item["path"].startswith(expected_prefix):
        print(f"ERROR: template {name!r} path must start with {expected_prefix}", file=sys.stderr)
        sys.exit(1)
    placements = item.get("allowed_datastores", [item["datastore"]])
    if not isinstance(placements, list) or not placements:
        print(f"ERROR: template {name!r} allowed_datastores must be a non-empty list", file=sys.stderr)
        sys.exit(1)
    bad = [x for x in placements if x not in allowed_ds]
    if bad:
        print(f"ERROR: template {name!r} allowed_datastores contains unknown datastore(s): {bad}", file=sys.stderr)
        sys.exit(1)
PY
}

detect_hermes_ip() {
  if [ -n "${HERMES_IP:-}" ]; then
    return 0
  fi

  if command -v ip >/dev/null 2>&1; then
    # Some iproute2 builds do not accept hostnames in `ip route get`.
    # Try direct first, then resolve to IPv4 and retry.
    local route_target="$ESXI_HOST"
    local detected=""

    detected="$(ip route get "$route_target" 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -n1 || true)"

    if [ -z "$detected" ] && command -v getent >/dev/null 2>&1; then
      route_target="$(getent ahostsv4 "$ESXI_HOST" | awk 'NR==1 {print $1}')"
      if [ -n "$route_target" ]; then
        detected="$(ip route get "$route_target" 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -n1 || true)"
      fi
    fi

    if [ -n "$detected" ]; then
      HERMES_IP="$detected"
      export HERMES_IP
    fi
  fi

  if [ -z "${HERMES_IP:-}" ]; then
    echo "ERROR: could not auto-detect HERMES_IP. Set it manually in install.env" >&2
    exit 1
  fi
}
