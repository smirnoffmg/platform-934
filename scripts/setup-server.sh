#!/usr/bin/env bash
# Provision a fresh VPS as a VPN server.
#
# Usage: scripts/setup-server.sh <ip> <root-password>
#
# What it does:
#   1. Copies your local SSH public key to root@<ip> using the password.
#   2. Writes ansible/inventory/hosts.prod.ini.
#   3. Runs the Ansible playbook with ansible/vars/real.secret.yml.
#
# Prerequisites: sshpass, ansible-playbook, real.secret.yml filled in.

set -euo pipefail

IP="${1:?Usage: $0 <ip> <root-password>}"
PASSWORD="${2:?Usage: $0 <ip> <root-password>}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$REPO_ROOT/ansible/vars/real.secret.yml"
INVENTORY="$REPO_ROOT/ansible/inventory/hosts.prod.ini"

for bin in sshpass ansible-playbook; do
    command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not found — install it first" >&2; exit 1; }
done

[ -f "$SECRETS" ] || {
    echo "ERROR: $SECRETS not found — fill it in before provisioning (see ansible/vars/main.yml for required keys)" >&2
    exit 1
}

echo "=== Copying SSH key to root@$IP ==="
sshpass -p "$PASSWORD" ssh-copy-id \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@"$IP"

printf '[vps]\n%s ansible_user=root\n' "$IP" > "$INVENTORY"
echo "Inventory written to $INVENTORY"

echo "=== Provisioning $IP ==="
ansible-playbook \
    -i "$INVENTORY" \
    "$REPO_ROOT/ansible/playbook.yml" \
    -e "@$SECRETS"

echo ""
echo "=== Done: $IP is provisioned and running ==="
