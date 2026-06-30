#! /bin/sh
#
# SPDX-License-Identifier: BSD-0-Clause OR MIT-0
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
#
# vm-do-sudo.sh — make sudo available and configure group sudo access
#
# Modes:
#   0 = require password for admin group (DEFAULT)
#   1 = NOPASSWD for admin group (ALL)   [broad]
#   2 = NOPASSWD only for approved commands (whitelist)
#
# Usage (run as root):
#   ./vm-do-sudo.sh <username> <mode>
# Example:
#   ./vm-do-sudo.sh deploy 2
#
# Notes:
# - This writes a dedicated sudoers rule file in /etc/sudoers.d when possible.
# - Whitelisted commands are written as broad-but-targeted patterns, e.g.:
#     /usr/sbin/pkg install *, /usr/bin/apt-get install *
# TODO: can extend WHITELIST_CMD_* section below for additional commands.
set -eu

USER_NAME="${1:-}"
MODE="${2:-0}"

if [ -z "$USER_NAME" ]; then
  printf '%s\n' "Usage: $0 <username> <mode(0|1|2)>" >&2
  exit 2
fi

case "$MODE" in 0|1|2) : ;; *) printf '%s\n' "Mode must be 0,1,or2" >&2; exit 2 ;; esac

if [ "$(id -u)" != "0" ]; then
  printf '%s\n' "Run this as root." >&2
  exit 1
fi

OS="$(uname -s 2>/dev/null || echo unknown)"

# helper: fail with message
die_stub(){ printf "::error title='ERROR':: %s\n" "$*" >&2; exit 1; }

install_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi

  printf '%s\n' "Installing sudo on: $OS"

  if printf '%s\n' "$OS" | grep -Eq 'FreeBSD|GhostBSD|DragonFly|MidnightBSD|NetBSD|OpenBSD|Bitrig'; then
    # FreeBSD/DragonFly: pkg
    if command -v pkg >/dev/null 2>&1; then
      pkg install -y sudo >/dev/null 2>&1 && return 0
    fi
    # Some older/variants: pkg_add / pkgin
    if command -v pkg_add >/dev/null 2>&1; then
      pkg_add sudo >/dev/null 2>&1 && return 0
    fi
    if command -v pkgin >/dev/null 2>&1; then
      pkgin -y install sudo >/dev/null 2>&1 && return 0
    fi
  fi

  if printf '%s\n' "$OS" | grep -Eq 'SunOS'; then
    # illumos/OpenIndiana: IPS/pkgs vary; try common pkg(1) paths if present.
    if command -v pkg >/dev/null 2>&1; then
      pkg install -y system/sudo >/dev/null 2>&1 || pkg install -y sudo >/dev/null 2>&1 || true
      command -v sudo >/dev/null 2>&1 && return 0
    fi
    printf '%s\n' "No supported installer path found for SunOS/Solaris image." >&2
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y sudo >/dev/null 2>&1 && return 0
  fi

  printf '%s\n' "No supported sudo installer detected on this OS/image ($OS). Install sudo manually." >&2
  return 1
}

detect_admin_group() {
  if command -v getent >/dev/null 2>&1 && getent group sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo";
  elif [ -f /etc/group ] && grep -q '^wheel:' /etc/group 2>/dev/null; then
    printf '%s\n' "wheel";
  else
    printf '%s\n' "wheel";
  fi
}

add_user_to_admin_group() {
  GROUP=$(detect_admin_group)

  printf '%s\n' "Ensuring user '$USER_NAME' is in group '$GROUP'"

  if command -v usermod >/dev/null 2>&1; then
    getent group "$GROUP" >/dev/null 2>&1 || groupadd "$GROUP" >/dev/null 2>&1 || true
    usermod -aG "$GROUP" "$USER_NAME" >/dev/null 2>&1 || die_stub "User promotion to sudo failed" ;
    return 0
  fi

  if command -v pw >/dev/null 2>&1; then
    pw groupmod "$GROUP" -m "$USER_NAME" >/dev/null 2>&1 || die_stub "User promotion to sudo failed" ;
    return 0
  fi

  printf '%s\n' "Could not automatically add user to group on this image." >&2
  return 1
}

ensure_sudoers_rule() {
  # Prefer sudoers.d include
  SUDOERS_D="/etc/sudoers.d"
  FILE="$SUDOERS_D/99-$USER_NAME-admin"

  # Determine admin group name (wheel/sudo)
  GROUP=$(detect_admin_group)

  # NOPASSWD policy
  if [ "$MODE" = "1" ]; then
    RULE="%$GROUP ALL=(ALL) NOPASSWD: ALL"
  elif [ "$MODE" = "2" ]; then
    # Whitelist commands allowed without password.
    # We express these as Cmnd_Alias entries with argument wildcards.
    #
    # The patterns below are intentionally conservative: they allow running
    # package installers with common subcommands (install/update/upgrade)
    # but not arbitrary system commands.
    #
    # Extend WHITELIST below if you need more commands.
    WHITELIST_PKG_INSTALL=""
    WHITELIST_APT_INSTALL=""
    WHITELIST_APK_INSTALL=""
    WHITELIST_NPM_INSTALL=""
    WHITELIST_PIP_INSTALL=""

    WHITELIST_PKG_UPDATE=""
    WHITELIST_APT_UPDATE=""

    # Only include patterns that map to binaries we actually have.
    # (This keeps sudoers clean on images that lack certain package managers.)
    if [ -x /usr/sbin/pkg ] || command -v pkg >/dev/null 2>&1; then
      # FreeBSD-ish pkg(8): usually /usr/sbin/pkg
      PKG_BIN="$(command -v pkg 2>/dev/null || echo /usr/sbin/pkg)"
      WHITELIST_PKG_INSTALL="$PKG_BIN install *"
      WHITELIST_PKG_UPDATE="$PKG_BIN update *"
    fi

    if command -v apt-get >/dev/null 2>&1; then
      APT_GET_BIN="$(command -v apt-get)"
      WHITELIST_APT_INSTALL="$APT_GET_BIN install *"
      # Optional: you can add update/upgrade as well:
      WHITELIST_APT_UPDATE="$APT_GET_BIN update, $APT_GET_BIN upgrade"
    fi

    if command -v apk >/dev/null 2>&1; then
      APK_BIN="$(command -v apk)"
      WHITELIST_APK_INSTALL="$APK_BIN add *"
    fi

    # (Optional examples) Uncomment if you want these included:
    # if command -v npm >/dev/null 2>&1; then
    #   NPM_BIN="$(command -v npm)"
    #   WHITELIST_NPM_INSTALL="$NPM_BIN i *"
    # fi
    # if command -v pip >/dev/null 2>&1; then
    #   PIP_BIN="$(command -v pip)"
    #   WHITELIST_PIP_INSTALL="$PIP_BIN install *"
    # fi

    # Build Cmnd_Alias lines. If nothing matches, we fallback to refusing NOPASSWD.
    CMD_LIST=""
    if [ -n "$WHITELIST_PKG_INSTALL" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_PKG_INSTALL"; fi
    if [ -n "$WHITELIST_PKG_UPDATE" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_PKG_UPDATE"; fi
    if [ -n "$WHITELIST_APT_INSTALL" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_APT_INSTALL"; fi
    if [ -n "$WHITELIST_APT_UPDATE" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_APT_UPDATE"; fi
    if [ -n "$WHITELIST_APK_INSTALL" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_APK_INSTALL"; fi
    if [ -n "$WHITELIST_NPM_INSTALL" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_NPM_INSTALL"; fi
    if [ -n "$WHITELIST_PIP_INSTALL" ]; then CMD_LIST="$CMD_LIST, $WHITELIST_PIP_INSTALL"; fi

    # Trim leading comma+space
    CMD_LIST="$(printf '%s\n' "$CMD_LIST" | sed 's/^, *//')"

    if [ -z "$CMD_LIST" ]; then
      # No package manager found => no whitelist (but still allow admin group with password).
      # This avoids writing an empty Cmnd_Alias that could confuse behavior.
      RULE="%$GROUP ALL=(ALL) ALL"
    else
      # Allow NOPASSWD only for whitelisted commands; keep everything else password-gated.
      # Also allow the group to run "sudo -n true" etc would not be needed; keep narrow.
      RULE="%$GROUP ALL=(ALL) ALL
%$GROUP ALL=(ALL) NOPASSWD: $CMD_LIST"
      # Some sudo versions dislike multi-line in a single variable for sudoers.d; write as literal below.
    fi
  else
    # MODE=0: password for admin group (no NOPASSWD)
    RULE="%$GROUP ALL=(ALL) ALL"
    printf "::warning title='SUDO-INTERACTIVE'::%s\n" "Interactive mode for sudo is intended for testing interactively, and can cause hangs when run in headless CI pipelines.";
  fi

  # If /etc/sudoers.d exists, use it.
  if [ -d "$SUDOERS_D" ]; then
    # e.g., can assume mkdir -p "$SUDOERS_D" >/dev/null 2>&1 || true
    umask 022
    # Write rule atomically if possible
    tmp="${FILE}.tmp.$$"
    # If MODE=2 and whitelist exists, RULE may contain newlines; preserve them.
    # shellcheck disable=SC2059
    printf "%s\n" "$RULE" > "$tmp"
    chmod 0440 "$tmp" >/dev/null 2>&1 || die_stub "sudoers could not be chmoded" ;
    mv "$tmp" "$FILE"
    chmod 0440 "$FILE" >/dev/null 2>&1 || true ;
    # early cleanup
    { chmod 600 "$tmp" >/dev/null 2>&1 || die_stub "TMP could not be un-chmoded (for cleanup)" ;
      rm -f "$tmp" >/dev/null 2>&1 || die_stub "TMP could not cleaned up" ;}

    # Validate sudoers if visudo exists
    if command -v visudo >/dev/null 2>&1; then
      visudo -c >/dev/null 2>&1 || die_stub "sudoers validation failed" ;
    fi
    return 0
  fi

  # Fallback: /etc/sudoers direct edit (least preferred)
  printf '::warning::%s\n' "No /etc/sudoers.d directory; falling back to appending to /etc/sudoers."
  SUDOERS="/etc/sudoers"
  SUDOERS_BACKUP_PATH="$SUDOERS.bak.$(date +%s)"
  if [ -f "$SUDOERS" ]; then
    cp -fp "$SUDOERS" "${SUDOERS_BACKUP_PATH}" >/dev/null 2>&1 || die_stub "Could not backup old sudoers" ;
    if ! printf '%s\n' "$RULE" >> "$SUDOERS"; then
      mv -f "${SUDOERS_BACKUP_PATH}" "$SUDOERS" >/dev/null 2>&1 || die_stub "sudoers restore from backup failed" ;
      die_stub "Could not update sudoers" ;
    fi
  else
    if ! printf '%s\n' "$RULE" > "$SUDOERS"; then
      die_stub "Could not update sudoers" ;
    fi
  fi
  # Validate sudoers if visudo exists
  if command -v visudo >/dev/null 2>&1; then
    if ! visudo -c >/dev/null 2>&1; then
      if [ -f "$SUDOERS_BACKUP_PATH" ]; then
        mv -f "${SUDOERS_BACKUP_PATH}" "$SUDOERS" >/dev/null 2>&1 || die_stub "sudoers restore from backup failed" ;
      fi
      die_stub "sudoers validation failed" ;  # still fail on successful restore
    fi
  fi
}

main() {
  install_sudo
  add_user_to_admin_group
  ensure_sudoers_rule

  printf '%s\n' "sudo ready"
}

main "$@"

#cleanup
unset MODE
unset die_stub 2>/dev/null || true
unset ensure_sudoers_rule 2>/dev/null || true
unset detect_admin_group 2>/dev/null || true
unset install_sudo 2>/dev/null || true
