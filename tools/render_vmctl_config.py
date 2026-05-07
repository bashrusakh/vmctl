#!/usr/bin/env python3
import json
import os
import sys
import yaml

def csv(name: str):
    return [x.strip() for x in os.environ.get(name, "").split(",") if x.strip()]

def main():
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
        "security": {
            "allow_direct_esxi": False,
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
    }
    sys.stdout.write(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))

if __name__ == "__main__":
    main()
