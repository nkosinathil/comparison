#!/usr/bin/env bash
set -euo pipefail

if ! command -v ssh-copy-id >/dev/null 2>&1; then
  echo "ERROR: ssh-copy-id is required but was not found." >&2
  exit 1
fi

KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
PUB_KEY="${KEY_PATH}.pub"

if [ ! -f "$PUB_KEY" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
fi

if [ "$#" -eq 0 ]; then
  cat >&2 <<'USAGE'
Usage:
  ./setup-ssh-keys.sh user1@host1 [user2@host2 ...]

Example:
  ./setup-ssh-keys.sh deploy@app.example.com deploy@python.example.com ssoadmin@192.168.1.59
USAGE
  exit 1
fi

for target in "$@"; do
  echo "==> Configuring SSH key login for ${target}"
  ssh-copy-id -i "$PUB_KEY" -o StrictHostKeyChecking=accept-new "$target"

  if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$target" "echo ok" >/dev/null 2>&1; then
    echo "    OK: key-based login verified for ${target}"
  else
    echo "    ERROR: key-based login verification failed for ${target}" >&2
    exit 1
  fi
done
