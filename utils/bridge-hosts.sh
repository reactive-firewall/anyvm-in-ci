#! /bin/bash
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

test -x "$(command -v scp)" || exit 126 ;
set -eu

# bridge-hosts.sh

# CAUTION: WIP!

# 6e. Merge host /etc/hosts into guest's /etc/hosts (best-effort, safer merge)
# - preserves guest's essential localhost and virtualization entries
# - adds host entries that don't conflict with guest localhost/virtualization
# - preserves "blackhole" localhost-style entries from host (e.g. somehost -> 127.0.0.1 or ::1)
#
# Assumptions (reasonable defaults):
# - VM ssh reachable as root@"$VM_SSH_HOST" on port $VM_SSH_PORT using key $EPHEM_KEY
# - scp/ssh available locally and on guest
#
# Behavior summary:
# 1) Copy host /etc/hosts to guest temporary file
# 2) On guest, create a sanitized guest /etc/hosts snapshot of existing content,
#    keeping lines that define canonical localhost and typical virtualization entries.
# 3) Append host entries that do not conflict with the preserved guest localhost/virtualization names.
# 4) Preserve host "blackhole" mappings (to 127.0.0.* or ::1) unless they would overwrite a preserved
#    guest localhost/virtualization name.
#
# Note: Best-effort — if any command fails we continue (nonfatal), but critical failures are reported.

# TODO: add check for EPHEM_KEY file or abort
if [ -f "${EPHEM_KEY:-}" ]; then
  true ;
else
  printf '::warning:: %s\n' "EPHEM_KEY not set or file not found; skipping hosts merge." >&2
  exit 0
fi

SSH_BOOT_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${EPHEM_KEY:-}"
VM="${VM_SSH_HOST:-localhost}"

# helper: remote run (non-fatal)
_remote_run() {
  ssh $SSH_BOOT_OPTS -p ${VM_SSH_PORT:-22} root@"$VM" "$@" || true
}

# copy host file to guest /tmp/hosts.from_host
if [ -f /etc/hosts ]; then
  scp $SSH_BOOT_OPTS -P ${VM_SSH_PORT:-22} /etc/hosts root@"$VM":/tmp/hosts.from_host || true
else
  printf '::warning:: %s\n' "/etc/hosts not found locally; nothing to merge." >&2
  exit 0
fi

# remote merge script: run on guest (idempotent-ish)
_remote_run bash -s <<'REMOTE_EOF' || true
set -eu

HOSTS_FROM_HOST=/tmp/hosts.from_host
GUEST_HOSTS=/etc/hosts
BACKUP_HOSTS=/etc/hosts.bak-from-merge-$(date +%s)

# If copied file missing, exit
if [ ! -f "$HOSTS_FROM_HOST" ]; then
  printf '::warning:: %s\n' "No host copy found at $HOSTS_FROM_HOST; aborting merge." >&2
  exit 0
fi

# 1) Backup current guest hosts
cp -p "$GUEST_HOSTS" "$BACKUP_HOSTS" || { printf '%s\n' "Failed to backup $GUEST_HOSTS"; exit 0; }

# 2) Define patterns/names we consider essential for the guest and must not be overwritten:
#    - localhost names: localhost, localhost.localdomain, ip6-localhost, ip6-loopback
#    - virtualization-specific names often present on VMs (try to detect common ones)
#    - preserve any entry mapped to 127.0.0.1 or ::1 in the guest (explicit guest blackhole)
ESSENTIAL_NAMES=$(awk '
  /^[[:space:]]*#/ { next }
  NF >= 2 {
    ip=$1
    for (i=2;i<=NF;i++) {
      name=$i
      if (ip ~ /^127\./ || ip == "127.0.0.1" || ip == "::1") {
        print name
      } else if (name ~ /localhost/ || name ~ /localdomain/ || name ~ /ip6-(localhost|loopback)/) {
        print name
      }
    }
  }
' "$GUEST_HOSTS" | sort -u)

# Build a grep pattern for essential names (if any)
ESSENTIAL_GREP=""
if [ -n "$ESSENTIAL_NAMES" ]; then
  # join names with |, escape dots
  PATTERN="$(echo "$ESSENTIAL_NAMES" | sed 's/[].[*^$\/]/\\&/g' | paste -sd'|' -)"
  ESSENTIAL_GREP="$PATTERN"
fi

# 3) Create a new hosts file starting from the guest backup but removing any host-provided
#    lines that would clobber essential names.
TMP_NEW="/tmp/hosts.new.$$"

# Start with header and preserved guest content (we will remove from host contributions)
cp "$BACKUP_HOSTS" "$TMP_NEW"

# 4) Process the host-supplied file and append only safe entries:
#    - If host line maps a name in ESSENTIAL_NAMES, skip that line (do not overwrite guest)
#    - Otherwise, append the line but avoid duplicate name entries (prefer guest's existing)
awk -v ess="$ESSENTIAL_GREP" '
  function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
  BEGIN{
    FS="[ \t]+"; OFS="\t"
  }
  NR==FNR {
    # first pass: read existing (current guest) names into seen[]
    if ($0 ~ /^[[:space:]]*#/ || NF==0) next
    ip=$1
    for (i=2;i<=NF;i++) {
      name=$i
      seen[tolower(name)]=1
    }
    next
  }
  {
    # second pass: host-supplied lines
    line=$0
    if (line ~ /^[[:space:]]*#/ || NF==0) next
    ip=$1
    skip=0
    for (i=2;i<=NF;i++) {
      name=tolower($i)
      if (name in seen) { skip=1; break }
      # if name is essential (matches ess), skip
      if (ess != "" && name ~ ess) { skip=1; break }
    }
    if (!skip) print line
  }
' "$BACKUP_HOSTS" "$HOSTS_FROM_HOST" >> "$TMP_NEW" || true

# 5) Deduplicate lines for identical names: keep the first occurrence (guest-preferred)
#    We'll produce final file by walking TMP_NEW and ensuring each hostname emitted once.
awk '
  /^[[:space:]]*#/ { print; next }
  NF==0 { print; next }
  {
    ip=$1
    out=""
    for (i=2;i<=NF;i++) {
      name=$i
      lname=tolower(name)
      if (!(lname in seen)) {
        seen[lname]=1
        out = out (out=="" ? "" : " ") name
      }
    }
    if (out != "") print ip, out
  }
' "$TMP_NEW" > "${TMP_NEW}.dedup" || {
  printf '::warning:: %s\n' "Failed to deduplicate merged hosts; leaving $GUEST_HOSTS unchanged. THIS MAY HAVE SECURITY IMPACTS!" >&2
  rm -f "${TMP_NEW}.dedup" "$TMP_NEW"
  exit 0
}
[ -s "${TMP_NEW}.dedup" ] || {
  printf '::warning:: %s\n' "Generated hosts file is empty; leaving $GUEST_HOSTS unchanged. THIS MAY HAVE SECURITY IMPACTS!" >&2
  rm -f "${TMP_NEW}.dedup" "$TMP_NEW"
  exit 0
}

# 6) Atomically install new hosts file (fallback to non-atomic if needed)
if mv "${TMP_NEW}.dedup" "$GUEST_HOSTS".tmp && mv "$GUEST_HOSTS".tmp "$GUEST_HOSTS"; then
  printf '%s\n' "Merged hosts installed to $GUEST_HOSTS (backup at $BACKUP_HOSTS)"
else
  printf '::warning:: %s\n' "Atomic install failed; attempting non-atomic write." >&2
  cat "${TMP_NEW}.dedup" > "$GUEST_HOSTS" || { printf '%s\n' "Failed to write $GUEST_HOSTS"; exit 0; }
  printf '%s\n'  "Merged hosts written (backup at $BACKUP_HOSTS)"
fi

# 7) Clean up
rm -f "$HOSTS_FROM_HOST" "$TMP_NEW" "${TMP_NEW}.dedup" || true

REMOTE_EOF

# done
