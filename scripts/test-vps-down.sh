#!/usr/bin/env bash
# Destroys all throwaway droplets created by scripts/test-vps-up.sh.
#
# Usage: scripts/test-vps-down.sh
#   FORCE=1  skip the confirmation prompt

set -euo pipefail

tag="ansible-test"
inventory_file="$(dirname "$0")/../ansible/inventory/hosts.test.ini"

if ! doctl account get >/dev/null 2>&1; then
  echo "doctl is not authenticated. Run 'doctl auth init' first." >&2
  exit 1
fi

matches="$(doctl compute droplet list --tag-name "$tag" --format ID,Name,PublicIPv4,Region,Status --no-header)"
if [ -z "$matches" ]; then
  echo "No droplets tagged '$tag' found."
  exit 0
fi

echo "About to destroy:"
echo "$matches"

if [ "${FORCE:-0}" != "1" ]; then
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in
    [yY]) ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

doctl compute droplet delete --force --tag-name "$tag"
rm -f "$inventory_file"

echo "Destroyed all '$tag' droplets and removed $inventory_file."
