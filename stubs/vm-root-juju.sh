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

# vm-root-juju.sh -- harden SSH against trivial root access
# Targets: Linux, BSDs, Solaris/Illumos, Darwin, Haiku, BlissOS

set -eu

SSHD_CONFIG="/etc/ssh/sshd_config"
TMP_CONFIG="/etc/ssh/sshd_config.tmp"

# 1. Pre-flight checks
if [ ! -f "$SSHD_CONFIG" ]; then
    printf "::debug::%s\n" "Config file $SSHD_CONFIG not found. Skipping."
    exit 0
fi

if [ ! -w "$SSHD_CONFIG" ]; then
    printf "::debug::%s\n" "Config file $SSHD_CONFIG is not writable. Skipping."
    exit 1
fi

# 2. Create a working copy (preserves permissions)
cp -p "$SSHD_CONFIG" "$TMP_CONFIG" 2>/dev/null || cp "$SSHD_CONFIG" "$TMP_CONFIG"

# Helper function to ensure a setting is present and correct
set_ssh_config() {
    key="$1"
    value="$2"
    full_setting="$key $value"

    # 1. Exact match check (Idempotency)
    if grep -qFx "$full_setting" "$TMP_CONFIG"; then
        return 0
    fi

    # 2. Special handling for SetEnv to avoid overwriting other environment variables
    if [ "$key" = "SetEnv" ]; then
        # Check if this specific variable (e.g., LD_PRELOAD) is already set
        if grep -q "^[[:space:]]*SetEnv[[:space:]]*$value" "$TMP_CONFIG"; then
            return 0
        fi
        # If it exists but has a different value, replace only that specific variable line
        # This regex looks for SetEnv followed by the variable name (e.g., LD_PRELOAD)
        var_name=$(printf '%s' "$value" | cut -d= -f1)
        if grep -q "^[[:space:]]*SetEnv[[:space:]]*$var_name=" "$TMP_CONFIG"; then
            sed "s|^[[:space:]]*SetEnv[[:space:]]*$var_name=.*|$full_setting|" "$TMP_CONFIG" > "$TMP_CONFIG.bak"
            mv "$TMP_CONFIG.bak" "$TMP_CONFIG"
        else
            # Variable not found, append it
            printf '\n%s\n' "$full_setting" >> "$TMP_CONFIG"
        fi
    else
        # Standard handling for single-instance keys
        if grep -q "^[[:space:]]*$key" "$TMP_CONFIG"; then
            sed "s|^[[:space:]]*$key.*|$full_setting|" "$TMP_CONFIG" > "$TMP_CONFIG.bak"
            mv "$TMP_CONFIG.bak" "$TMP_CONFIG"
        else
            printf '\n%s\n' "$full_setting" >> "$TMP_CONFIG"
        fi
    fi
    printf "::debug::%s\n" "Applied: $full_setting"
}

# 3. Apply General Hardening (Including former TODOs)
settings="
PasswordAuthentication no
IgnoreRhosts yes
IgnoreUserKnownHosts yes
RekeyLimit default 1h30m
X11Forwarding no
AuthenticationMethods publickey
LoginGraceTime 30
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
MaxStartups 6:20:24
SetEnv LD_PRELOAD=
"

printf '%s' "$settings" | while read -r line; do
    [ -z "$line" ] && continue
    # Split line into key and value for the helper function
    set_ssh_config $line
done

# 4. Root Access Restrictions
set_ssh_config "PermitRootLogin" "prohibit-password"
set_ssh_config "DenyUsers" "root"

# 5. Final Atomic Deployment
cp -p "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" 2>/dev/null || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
mv "$TMP_CONFIG" "$SSHD_CONFIG"

printf "::debug::%s\n" "SSHD hardening complete. (will restart sshd)"

# do some cleanup first
unset settings
unset TMP_CONFIG
unset set_ssh_config 2>/dev/null || true

# reload sshd safely (try multiple names)
# Try commands safely: run "$@" and return 0/1 (no exit)
_try() {
  if command -v "$1" >/dev/null 2>&1; then
    shift
    "$@" >/dev/null 2>&1 && return 0 || return 1
  fi
  return 2
}

# Try a list of command invocations (each invocation is a single string)
_try_list() {
  for cmd in "$@"; do
    # shellcheck disable=SC2086
    sh -c "$cmd" >/dev/null 2>&1 && return 0
  done
  return 1
}

# Common service names to try (order: typical -> fallback)
SERVICE_NAMES="sshd ssh"

# 1) systemctl (Linux)
if command -v systemctl >/dev/null 2>&1; then
  for name in $SERVICE_NAMES; do
    _try systemctl systemctl try-reload-or-restart "${name}.service" && exit 0
    _try systemctl systemctl reload "${name}.service" && exit 0
    _try systemctl systemctl restart "${name}.service" && exit 0
  done
fi

# 2) rc.d / service wrapper used on FreeBSD/OpenBSD/NetBSD
# On BSDs, `service name action` is typical; on some systems action "reload" may not exist.
if command -v service >/dev/null 2>&1; then
  for name in $SERVICE_NAMES; do
    _try service service "$name" reload && exit 0
    _try service service "$name" restart && exit 0
    # On some systems the service control is in /etc/rc.d/ or /usr/sbin/rcctl (OpenBSD)
  done
fi

# 3) rcctl (OpenBSD) — prefer explicit rcctl if present
if command -v rcctl >/dev/null 2>&1; then
  for name in $SERVICE_NAMES; do
    _try rcctl rcctl reload "$name" && exit 0
    _try rcctl rcctl restart "$name" && exit 0
  done
fi

# 4) /etc/rc.d or /usr/local/etc/rc.d scripts (FreeBSD-style direct script)
for name in $SERVICE_NAMES; do
  if [ -x "/etc/rc.d/$name" ]; then
    _try_list "/etc/rc.d/$name reload" "/etc/rc.d/$name restart" && exit 0
  fi
  if [ -x "/usr/local/etc/rc.d/$name" ]; then
    _try_list "/usr/local/etc/rc.d/$name reload" "/usr/local/etc/rc.d/$name restart" && exit 0
  fi
done

# 5) OpenSSH's sshd direct signal (safe reload using SIGHUP) — will not restart if binary name differs
for candidate in /usr/sbin/sshd /usr/local/sbin/sshd /sbin/sshd /usr/sbin/ssh; do
  if [ -x "$candidate" ]; then
    # Find master pid (sshd -T is not used). Use pgrep for sshd process.
    if command -v pgrep >/dev/null 2>&1; then
      pid=$(pgrep -x sshd || true)
    else
      pid=$(ps ax | awk '/[s]shd/ {print $1; exit}' || true)
    fi
    if [ -n "$pid" ]; then
      kill -HUP "$pid" >/dev/null 2>&1 && exit 0
    fi
  fi
done

# 6) Haiku (launch_daemon control via haiku-specific tools)
# Haiku often runs services via launch_daemon; use `launchctl` if available (Haiku compatibility) or try haikucontrol.
if command -v launchctl >/dev/null 2>&1; then
  for name in $SERVICE_NAMES; do
    _try launchctl launchctl unload "/system/services/${name}" && _try launchctl launchctl load "/system/services/${name}" && exit 0
  done
fi
if command -v haikucontrol >/dev/null 2>&1; then
  for name in $SERVICE_NAMES; do
    _try haikucontrol haikucontrol restart "$name" && exit 0
  done
fi

# 7) Fall back: try common init scripts (SysV-style)
for name in $SERVICE_NAMES; do
  if [ -x "/etc/init.d/$name" ]; then
    _try_list "/etc/init.d/$name reload" "/etc/init.d/$name restart" && exit 0
  fi
done
