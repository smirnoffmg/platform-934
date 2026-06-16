#!/usr/bin/env bash
# Creates a throwaway DigitalOcean droplet for manual real-VPS role testing
# (see doc/product/03-features/0001-idempotent-ansible-playbook-core.md,
# the "Real VPS required" rows of the testing matrix).
#
# Not part of the production deploy path — FEAT-0001 explicitly excludes
# VPS/cloud provisioning from the playbook's scope. This is dev-only tooling.
#
# Requires: `doctl auth init` already run once (token lives in doctl's own
# config, not in this repo or the shell environment).
#
# Usage: scripts/test-vps-up.sh [ubuntu|debian]
#   DO_REGION  region slug (default: fra1)
#   DO_SIZE    size slug   (default: s-1vcpu-1gb)

set -euo pipefail

os="${1:-ubuntu}"
region="${DO_REGION:-fra1}"
size="${DO_SIZE:-s-1vcpu-1gb}"
tag="ansible-test"
inventory_file="$(dirname "$0")/../ansible/inventory/hosts.test.ini"

case "$os" in
  ubuntu) image="ubuntu-22-04-x64" ;;
  debian) image="debian-12-x64" ;;
  *)
    echo "Usage: $0 [ubuntu|debian]" >&2
    exit 1
    ;;
esac

if ! doctl account get >/dev/null 2>&1; then
  echo "doctl is not authenticated. Run 'doctl auth init' first." >&2
  exit 1
fi

ssh_key_ids="$(doctl compute ssh-key list --format ID --no-header | paste -sd, -)"
if [ -z "$ssh_key_ids" ]; then
  echo "No SSH keys on your DO account. Upload one first: doctl compute ssh-key import" >&2
  exit 1
fi

name="ansible-test-${os}-$(date +%s)"

echo "Creating $name ($image, $size, $region)..."
result="$(doctl compute droplet create "$name" \
  --region "$region" \
  --size "$size" \
  --image "$image" \
  --ssh-keys "$ssh_key_ids" \
  --tag-names "$tag" \
  --wait \
  --format Name,PublicIPv4,Status \
  --no-header)"

ip="$(awk '{print $2}' <<<"$result")"

mkdir -p "$(dirname "$inventory_file")"
printf '[vps]\n%s ansible_user=root\n' "$ip" >"$inventory_file"

echo "Droplet ready: $name ($ip)"
echo "Inventory written to $inventory_file"
echo
echo "Run the playbook against it with:"
echo "  ansible-playbook -i $inventory_file ansible/playbook.yml -e @<your-real-vars-file>.yml"
echo
echo "Destroy it (and any other ansible-test droplets) with: scripts/test-vps-down.sh"
