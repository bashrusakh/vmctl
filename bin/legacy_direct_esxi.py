#!/usr/bin/env python3
import os
import subprocess


def _ssh_target(env: dict):
    user = env.get('ESXI_USER') or env.get('GOVC_USERNAME', '').split('@')[0] or 'root'
    host = env.get('ESXI_HOST')
    if not host:
        raise RuntimeError('ESXI_HOST is required')
    port = str(env.get('ESXI_SSH_PORT', '22'))
    key = os.path.expanduser(env.get('ESXI_SSH_KEY', '~/.ssh/id_ed25519'))
    return user, host, port, key


def run_ssh(env: dict, remote_cmd: str, check: bool = True):
    if not env.get('ALLOW_DIRECT_ESXI'):
        raise RuntimeError('direct ESXi shell commands are disabled (use --allow-direct-esxi or config.security.allow_direct_esxi=true)')
    user, host, port, key = _ssh_target(env)
    cmd = ['ssh', '-i', key, '-p', port, f'{user}@{host}', remote_cmd]
    return subprocess.run(cmd, check=check, capture_output=True, text=True)
