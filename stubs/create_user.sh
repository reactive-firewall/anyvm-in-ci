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

set -eu

# read inputs
USERNAME="${1:-runner}"
USER_PUB_IN="${2:-}"

# helper: conditional diagnostic with message
debug_remote_log(){ if [ "${DEBUG:-0}" -eq 1 ]; then printf '::debug::%s\n' "$*" ; fi; }

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
      printf "::error title='USER-ERR':: %s\n" "Error: key file was empty or unreadable." >&2
      exit 1
    fi
    if ! is_ssh_pubkey_line "$NEW_PUB"; then
      printf "::error title='USER-ERR':: %s\n" "Error: file contents do not look like an SSH public key." >&2
      exit 1
    fi
    printf '%s\n' "$NEW_PUB"
    return 0
  fi

  # Otherwise $in is presumed to be the key string; validate shape.
  if [ -z "$in" ] || ! is_ssh_pubkey_line "$in"; then
    printf "::error title='USER-ERR':: %s\n" "Error: input does not look like an SSH public key." >&2
    exit 1
  fi

  # Ensure it has at least "type blob" fields.
  # POSIX sh: use set -- to split on IFS (whitespace).
  set -- $in
  if [ $# -lt 2 ]; then
    printf "::error title='USER-ERR':: %s\n" "Error: SSH public key must contain at least 2 fields (type and blob)." >&2
    exit 1
  fi

  # Crude base64-ish sanity check on blob (no strict validation).
  blob="$2"
  # Blob should be non-empty and contain only base64 characters and '='.
  # If your system lacks grep -E, this still works with basic grep.
  case "$blob" in
    ''|*[!A-Za-z0-9+/=]*)
      printf "::error title='USER-ERR':: %s\n" "Error: SSH public key blob doesn't look base64-ish." >&2
      exit 1
      ;;
  esac

  printf '%s\n' "$in"
}

create_user() {
  _in_username=${1:-"runner"}
  _in_user_dir=${2:-"$USER_HOME_BASE_PATH/$_in_username"}
  _in_user_group=${3:-${1:-"runner"}}
  _in_user_shell=${4:-/bin/sh}


  # user exists?
  if id "$_in_username" >/dev/null 2>&1; then
    return 0
  fi

  # create group first if needed
  if ! getent group "$_in_user_group" >/dev/null 2>&1 2>/dev/null && ! grep -q "^$_in_user_group:" /etc/group 2>/dev/null; then
    # user group
    if command -v groupadd >/dev/null 2>&1; then
      # seealso https://man.openbsdhandbook.com/groupadd.8/
      groupadd "$_in_user_group" || true
    elif command -v addgroup >/dev/null 2>&1; then
      printf "::warning:: %s\n" "system has addgroup but support is not yet implemented" >&2;
      exit 1
    elif command -v pw >/dev/null 2>&1; then
      # FreeBSD: set default group (-g) to the new group
      # seealso https://man.freebsd.org/cgi/man.cgi?query=pw&format=html
      pw groupadd "$_in_user_group" || true
    fi
  fi
    # now user
    if command -v useradd >/dev/null 2>&1; then
      # see also https://man.openbsd.org/useradd
      useradd -m -d "$_in_user_dir" -g "$_in_user_group" -s /bin/sh "$_in_username" || true
    elif command -v adduser >/dev/null 2>&1; then
      _USER_TMP_DATA_FILE="./runner_$$.tmp"
      printf '%s::::::%s:%s:/bin/sh:\n' "$_in_username" "$_in_user_group" "$_in_user_dir" > "$_USER_TMP_DATA_FILE" || printf "::warning:: %s\n" "Failed to generate user ${_in_username:-} data file" >&2;
      adduser -s /bin/sh -w none -f $_USER_TMP_DATA_FILE || printf "::error:: %s\n" "Error: Failed to create user ${_in_username:-}" >&2;
      command -v pw >/dev/null 2>&1 && pw user show "$_in_username" || printf "::warning:: %s\n" "Error: Failed to verify user ${_in_username:-} was created" >&2;
      rm -f "${_USER_TMP_DATA_FILE:-}" 2>/dev/null || printf "::warning:: %s\n" "Failed to remove user ${_in_username:-} data file" >&2;
    elif command -v pw >/dev/null 2>&1; then
      # FreeBSD: set default group (-g) to the new group
      pw useradd -n "$_in_username" -m -d "$_in_user_dir" -s "$_in_user_shell" -g "$_in_user_group" -w none || printf "::error:: %s\n" "Error: Failed to create user ${_in_username:-}" >&2;
      pw user show "$_in_username" || printf "::error:: %s\n" "Error: Failed to verify user ${_in_username:-} was created" >&2;
    elif command -v dscl >/dev/null 2>&1; then
      # macOS user creation is a different API; don't try to force useradd/pw here
      dscl . -create "/Users/$_in_username" UserShell "$_in_user_shell"
      dscl . -create "/Users/$_in_username" NFSHomeDirectory "$_in_user_dir"
      dscl . -create "/Users/$_in_username" PrimaryGroupID 20
      dscl . -create "/Users/$_in_username" UniqueID "$(
        id -u 2>/dev/null || echo 500
      )" ;
    fi ;
}

debug_remote_log "Syncing user to VM" ;
# Normalize input public key (blob or file-path)
USER_PUB="$(normalize_and_validate_input "${USER_PUB_IN:-}")"
USERGROUP="${USERNAME:-runner}"
USER_HOME_BASE_PATH=""
if [ -d "/zroot" ]; then
  if [ -d "/zroot/home" ]; then
    USER_HOME_BASE_PATH="/zroot/home"
  fi;
fi ;
USER_HOME_BASE_PATH="${USER_HOME_BASE_PATH:-/home}"  # or could be '/Users'
# early cleanup of raw input
if [ -n "$USER_PUB_IN" ] && [ -f "$USER_PUB_IN" ] && [ -r "$USER_PUB_IN" ]; then
  rm -f "$USER_PUB_IN" 2>/dev/null || true ;
fi ;
unset USER_PUB_IN 2>/dev/null || true ;

# create user group (same name) + user: try useradd/useradd-alternate/adduser/pw

if ! id "$USERNAME" >/dev/null 2>&1; then
  # create user
  debug_remote_log "Creating empty user ($USERNAME)" ;
  create_user "$USERNAME" "$USER_HOME_BASE_PATH/$USERNAME" "$USERGROUP";
  if id "$USERNAME" >/dev/null 2>&1; then
    debug_remote_log "Created user successfully" ;
  else
    printf "::error title='NO-USER':: %s\n" "Failed to ensure a user was provisioned." >&2
    exit 1
  fi
fi

debug_remote_log "Looking for new home ($USER_HOME_BASE_PATH/$USERNAME/)" ;

if [ -d "$USER_HOME_BASE_PATH/$USERNAME" ]; then
  debug_remote_log "Found USER home" &
  debug_remote_log "Configuring user SSH key pair" ;

  mkdir -p "$USER_HOME_BASE_PATH"/"$USERNAME"/.ssh || true
  printf '%s\n' "$USER_PUB" > "$USER_HOME_BASE_PATH"/"$USERNAME"/.ssh/authorized_keys.new ;
  mv -f "$USER_HOME_BASE_PATH"/"$USERNAME"/.ssh/authorized_keys.new "$USER_HOME_BASE_PATH"/"$USERNAME"/.ssh/authorized_keys ;
  chmod 600 "$USER_HOME_BASE_PATH/$USERNAME"/.ssh/authorized_keys && chmod 700 "$USER_HOME_BASE_PATH/$USERNAME"/.ssh
  chown -R "$USERNAME":"$USERGROUP" "$USER_HOME_BASE_PATH/$USERNAME"/.ssh || true
  debug_remote_log "SSH user key-pair configured" ;

  # debug_remote_log "Configuring VM user configuration" ;
  # TODO: need to handle rest of https://docs.github.com/en/actions/reference/workflows-and-actions/variables#default-environment-variables
  # each value should be at-least set to a reasonable default in the startup rc so that the work

  debug_remote_log "Attempting to harden rest of user configuration" ;
  for _purge_file in .rhosts .shosts ; do
      if [ -f "$USER_HOME_BASE_PATH/$USERNAME/$_purge_file" ]; then
        debug_remote_log "found ~/$_purge_file (will remove)"
        rm -f "$USER_HOME_BASE_PATH/$USERNAME/$_purge_file" 2>/dev/null || true
      fi
  done
  debug_remote_log "Checking if we can use hushlogin"
  # Check if the line "Banner" is configured in /etc/ssh/sshd_config
  if [ -f /etc/ssh/sshd_config ]; then
    if grep -c "^[[:space:]]*Banner" /etc/ssh/sshd_config >/dev/null 2>&1; then
      debug_remote_log "generating ~/.hushlogin"
      printf "# reduce noise for CI logs\n" > "$USER_HOME_BASE_PATH/$USERNAME/.hushlogin" || true;
    fi
  fi
fi;

# early cleanup of vars
unset USER_PUB 2>/dev/null || true

debug_remote_log "Attempting to harden rest of system configuration" ;

# harden rest of config
for _purge_rfile in hosts.equiv shosts.equiv ; do
  if [ -f /etc/"$_purge_rfile" ]; then
    debug_remote_log "found /etc/$_purge_rfile (will remove)" ;
    rm -f /etc/"$_purge_rfile" || true ;
  fi
done

detect_admin_group() {
  if command -v getent >/dev/null 2>&1 && getent group sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo";
  elif [ -f /etc/group ] && grep -q '^wheel:' /etc/group 2>/dev/null; then
    printf '%s\n' "wheel";
  else
    printf '%s\n' "wheel";
  fi
}

# Ensure FreeBSD wheel handling + group membership (default group + supplementary)
if command -v pw >/dev/null 2>&1; then
  pw usermod "$USERNAME" -g "$USERGROUP" -G $(detect_admin_group),"$USERNAME" || true
  # critical to allow sudo usage on *bsd systems
  pw groupmod $(detect_admin_group) -m "$USERNAME" ;
fi
# more diognostics if in debug mode
if [ "${DEBUG:-0}" -eq 1 ]; then
  if command -v id >/dev/null 2>&1; then
    id "$USERNAME" || true
  fi
fi
# rest of the cleanup
unset USERGROUP
unset USER_HOME_BASE_PATH

printf '%s\n' "CI user ${USERNAME:-} synced to VM successfully" ;

unset USERNAME 2>/dev/null || true ;
unset create_user 2>/dev/null || true ;
unset debug_remote_log 2>/dev/null || true ;
unset is_ssh_pubkey_line 2>/dev/null || true ;
unset read_pub_from_file 2>/dev/null || true ;
unset normalize_and_validate_input 2>/dev/null || true ;
