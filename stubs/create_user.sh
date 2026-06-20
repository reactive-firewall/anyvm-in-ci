#!/usr/bin/env bash
set -eu
USERNAME="$1"
USER_PUB="$2"
# create user: try useradd/useradd-alternate/adduser/pw
if ! id "$USERNAME" >/dev/null 2>&1; then
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s /bin/sh "$USERNAME" || true
  elif command -v adduser >/dev/null 2>&1; then
    adduser -D -s /bin/sh "$USERNAME" || true
  elif command -v pw >/dev/null 2>&1; then
    pw useradd -n "$USERNAME" -m -s /bin/sh || true
  fi
fi
mkdir -p /home/"$USERNAME"/.ssh
printf '%s\n' "$USER_PUB" > /home/"$USERNAME"/.ssh/authorized_keys
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh || true
# FreeBSD wheel handling
if command -v pw >/dev/null 2>&1; then
  pw usermod "$USERNAME" -G wheel || true
fi
echo "CI user synced to VM"
