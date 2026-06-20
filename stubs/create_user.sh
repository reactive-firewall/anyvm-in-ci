#! /bin/sh
#
# SPDX-License-Identifier: BSD-3-Clause OR MIT
#
# Disclaimer of Warranties.
# A. YOU EXPRESSLY ACKNOWLEDGE AND AGREE THAT, TO THE EXTENT PERMITTED BY
#    APPLICABLE LAW, USE OF THIS SHELL SCRIPT AND ANY SERVICES PERFORMED
#    BY OR ACCESSED THROUGH THIS SHELL SCRIPT IS AT YOUR SOLE RISK AND
#    THAT THE ENTIRE RISK AS TO SATISFACTORY QUALITY, PERFORMANCE, ACCURACY AND
#    EFFORT IS WITH YOU.
#
# B. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THIS SHELL SCRIPT
#    AND SERVICES ARE PROVIDED "AS IS" AND "AS AVAILABLE", WITH ALL FAULTS AND
#    WITHOUT WARRANTY OF ANY KIND, AND THE AUTHOR OF THIS SHELL SCRIPT'S LICENSORS
#    (COLLECTIVELY REFERRED TO AS "THE AUTHOR" FOR THE PURPOSES OF THIS DISCLAIMER)
#    HEREBY DISCLAIM ALL WARRANTIES AND CONDITIONS WITH RESPECT TO THIS SHELL SCRIPT
#    SOFTWARE AND SERVICES, EITHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT
#    NOT LIMITED TO, THE IMPLIED WARRANTIES AND/OR CONDITIONS OF
#    MERCHANTABILITY, SATISFACTORY QUALITY, FITNESS FOR A PARTICULAR PURPOSE,
#    ACCURACY, QUIET ENJOYMENT, AND NON-INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# C. THE AUTHOR DOES NOT WARRANT AGAINST INTERFERENCE WITH YOUR ENJOYMENT OF THE
#    THE AUTHOR's SOFTWARE AND SERVICES, THAT THE FUNCTIONS CONTAINED IN, OR
#    SERVICES PERFORMED OR PROVIDED BY, THIS SHELL SCRIPT WILL MEET YOUR
#    REQUIREMENTS, THAT THE OPERATION OF THIS SHELL SCRIPT OR SERVICES WILL
#    BE UNINTERRUPTED OR ERROR-FREE, THAT ANY SERVICES WILL CONTINUE TO BE MADE
#    AVAILABLE, THAT THIS SHELL SCRIPT OR SERVICES WILL BE COMPATIBLE OR
#    WORK WITH ANY THIRD PARTY SOFTWARE, APPLICATIONS OR THIRD PARTY SERVICES,
#    OR THAT DEFECTS IN THIS SHELL SCRIPT OR SERVICES WILL BE CORRECTED.
#    INSTALLATION OF THIS THE AUTHOR SOFTWARE MAY AFFECT THE USABILITY OF THIRD
#    PARTY SOFTWARE, APPLICATIONS OR THIRD PARTY SERVICES.
#
# D. YOU FURTHER ACKNOWLEDGE THAT THIS SHELL SCRIPT AND SERVICES ARE NOT
#    INTENDED OR SUITABLE FOR USE IN SITUATIONS OR ENVIRONMENTS WHERE THE FAILURE
#    OR TIME DELAYS OF, OR ERRORS OR INACCURACIES IN, THE CONTENT, DATA OR
#    INFORMATION PROVIDED BY THIS SHELL SCRIPT OR SERVICES COULD LEAD TO
#    DEATH, PERSONAL INJURY, OR SEVERE PHYSICAL OR ENVIRONMENTAL DAMAGE,
#    INCLUDING WITHOUT LIMITATION THE OPERATION OF NUCLEAR FACILITIES, AIRCRAFT
#    NAVIGATION OR COMMUNICATION SYSTEMS, AIR TRAFFIC CONTROL, LIFE SUPPORT OR
#    WEAPONS SYSTEMS.
#
# E. NO ORAL OR WRITTEN INFORMATION OR ADVICE GIVEN BY THE AUTHOR
#    SHALL CREATE A WARRANTY. SHOULD THIS SHELL SCRIPT OR SERVICES PROVE DEFECTIVE,
#    YOU ASSUME THE ENTIRE COST OF ALL NECESSARY SERVICING, REPAIR OR CORRECTION.
#
#    Limitation of Liability.
# F. TO THE EXTENT NOT PROHIBITED BY APPLICABLE LAW, IN NO EVENT SHALL THE AUTHOR
#    BE LIABLE FOR PERSONAL INJURY, OR ANY INCIDENTAL, SPECIAL, INDIRECT OR
#    CONSEQUENTIAL DAMAGES WHATSOEVER, INCLUDING, WITHOUT LIMITATION, DAMAGES
#    FOR LOSS OF PROFITS, CORRUPTION OR LOSS OF DATA, FAILURE TO TRANSMIT OR
#    RECEIVE ANY DATA OR INFORMATION, BUSINESS INTERRUPTION OR ANY OTHER
#    COMMERCIAL DAMAGES OR LOSSES, ARISING OUT OF OR RELATED TO YOUR USE OR
#    INABILITY TO USE THIS SHELL SCRIPT OR SERVICES OR ANY THIRD PARTY
#    SOFTWARE OR APPLICATIONS IN CONJUNCTION WITH THIS SHELL SCRIPT OR
#    SERVICES, HOWEVER CAUSED, REGARDLESS OF THE THEORY OF LIABILITY (CONTRACT,
#    TORT OR OTHERWISE) AND EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE
#    POSSIBILITY OF SUCH DAMAGES. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION
#    OR LIMITATION OF LIABILITY FOR PERSONAL INJURY, OR OF INCIDENTAL OR
#    CONSEQUENTIAL DAMAGES, SO THIS LIMITATION MAY NOT APPLY TO YOU. In no event
#    shall THE AUTHOR's total liability to you for all damages (other than as may
#    be required by applicable law in cases involving personal injury) exceed
#    the amount of five dollars ($5.00). The foregoing limitations will apply
#    even if the above stated remedy fails of its essential purpose.
################################################################################

set -eu

USERNAME="${1:-CI}"
USER_PUB="${2:-}"

is_ssh_pubkey_line() {
  # Accept common SSH public key prefixes only (shape check).
  # Formats:
  #   ssh-rsa <blob> ...
  #   ssh-ed25519 <blob> ...
  #   ecdsa-sha2-nistp256 <blob> ...
  case "$1" in
    ssh-rsa\ *|ssh-dss\ *|ssh-ed25519\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Read first non-empty line from a .pub file (portable; avoids awk dependency nuances)
read_pub_from_file() {
  # shellcheck disable=SC2039
  # shellcheck disable=SC2094
  f="$1"
  # Busybox/posix sh portable loop
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '') continue ;;
      *) printf '%s\n' "$line"; return 0 ;;
    esac
  done < "$f"
  return 1
}

normalize_and_validate_input() {
  in="$1"
  if [ -n "$in" ] && [ -f "$in" ] && [ -r "$in" ]; then
    NEW_PUB="$(read_pub_from_file "$in")"
    if [ -z "${NEW_PUB:-}" ]; then
      echo "Error: key file was empty or unreadable." >&2
      exit 1
    fi
    if ! is_ssh_pubkey_line "$NEW_PUB"; then
      echo "Error: file contents do not look like an SSH public key." >&2
      exit 1
    fi
    printf '%s\n' "$NEW_PUB"
    return 0
  fi

  # Otherwise $in is presumed to be the key string; validate shape.
  if [ -z "$in" ] || ! is_ssh_pubkey_line "$in"; then
    echo "Error: input does not look like an SSH public key." >&2
    exit 1
  fi

  # Ensure it has at least "type blob" fields.
  # POSIX sh: use set -- to split on IFS (whitespace).
  set -- $in
  if [ $# -lt 2 ]; then
    echo "Error: SSH public key must contain at least 2 fields (type and blob)." >&2
    exit 1
  fi

  # Crude base64-ish sanity check on blob (no strict validation).
  blob="$2"
  # Blob should be non-empty and contain only base64 characters and '='.
  # If your system lacks grep -E, this still works with basic grep.
  case "$blob" in
    ''|*[!A-Za-z0-9+/=]*)
      echo "Error: SSH public key blob doesn't look base64-ish." >&2
      exit 1
      ;;
  esac

  printf '%s\n' "$in"
}

USER_PUB="$(normalize_and_validate_input "$IN")"

# create user group (same name) + user: try useradd/useradd-alternate/adduser/pw
if ! id "$USERNAME" >/dev/null 2>&1; then
  # create group first (if missing)
  if ! getent group "$USERNAME" >/dev/null 2>&1; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd "$USERNAME" || true
    elif command -v addgroup >/dev/null 2>&1; then
      addgroup "$USERNAME" || true
    elif command -v pw >/dev/null 2>&1; then
      pw groupadd "$USERNAME" || true
    else
      # fall back: best-effort, no-op if we can't create groups
      true
    fi
  fi

  # create user
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -g "$USERNAME" -s /bin/sh "$USERNAME" || true
  elif command -v adduser >/dev/null 2>&1; then
    adduser -D -s /bin/sh --ingroup "$USERNAME" "$USERNAME" || true
  elif command -v pw >/dev/null 2>&1; then
    # FreeBSD: set default group (-g) to the new group
    pw useradd -n "$USERNAME" -m -s /bin/sh -g "$USERNAME" || true
  fi
fi

mkdir -p /home/"$USERNAME"/.ssh
printf '%s\n' "$USER_PUB" > /home/"$USERNAME"/.ssh/authorized_keys
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh || true

unset USER_PUB 2>/dev/null || true

# Ensure FreeBSD wheel handling + group membership (default group + supplementary)
if command -v pw >/dev/null 2>&1; then
  pw usermod "$USERNAME" -g "$USERNAME" -G wheel,"$USERNAME" || true
fi

printf '%s\n' "CI user synced to VM"
