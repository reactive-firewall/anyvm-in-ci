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

# TODO: add check for SSH_EPHEMERAL_OPTS file or abort
# TODO: verify ANYVM_BRIDGE_HOSTS_FILE is set or abort

ANYVM_BRIDGE_HOSTS_FILE="${ANYVM_BRIDGE_HOSTS_FILE:-}"
SSH_EPHEMERAL_OPTS="${SSH_EPHEMERAL_OPTS:-}";
VM="${VM_SSH_HOST:-127.0.0.1}"
VM_SSH_PORT="${VM_SSH_PORT:-22}"

# helper: conditional diagnostic with message
debug_sub_log(){ if [ "${DEBUG}" ]; then printf '::debug:: %s\n' "$*" >&2; fi; }

# TODO: verify ANYVM_BRIDGE_HOSTS_FILE is a file that exists
debug_sub_log "Preparing script to bridge hosts on Guest VM" ;
BRIDGE_HOSTS_SCRIPT_PATH="$DATA_DIR/bridge_hosts_$$.sh"
cp -vf "${ANYVM_BRIDGE_HOSTS_FILE}" "$BRIDGE_HOSTS_SCRIPT_PATH"
debug_sub_log "=> Staged" & debug_log "..=> Setting Permissions on staged script" ;
chmod +x "$BRIDGE_HOSTS_SCRIPT_PATH"

debug_sub_log "Ready to transfer \"${BRIDGE_HOSTS_SCRIPT_PATH}\" to Guest VM" ;

debug_sub_log "=> Using runner /etc/hosts data to bridge hosts on Guest VM" ;
BRIDGE_HOSTS_DATA_PATH="$DATA_DIR/hosts_$$.data"

# copy host file to guest /tmp/hosts.from_host
if [ -f /etc/hosts ]; then
  cat <"/etc/hosts" >> "$BRIDGE_HOSTS_SCRIPT_PATH" ; # 'copy' but not permissions (by reading)
  debug_sub_log "..=> Data Staged"
  debug_sub_log "=> Ready to also transfer \"${BRIDGE_HOSTS_DATA_PATH}\" to Guest VM" ;
  debug_sub_log "....=> Waiting for transfer" ;
  scp $SSH_EPHEMERAL_OPTS -P ${VM_SSH_PORT:-22} "${BRIDGE_HOSTS_DATA_PATH}" root@"$VM":/tmp/hosts.from_host || printf '::warning:: %s\n' "failed to scp bridge-hosts data"
  scp $SSH_EPHEMERAL_OPTS -P $VM_SSH_PORT "$BRIDGE_HOSTS_SCRIPT_PATH" root@"$VM":/tmp/bridge-hosts.sh || printf '::warning:: %s\n' "failed to scp bridge-hosts script"
  debug_sub_log "..=> Transferred" & {rm -f "$BRIDGE_HOSTS_DATA_PATH" 2>/dev/null || true ;} & debug_log "..=> Waiting for bridging" &
  # remote merge script: run on guest (idempotent-ish)
  ssh $SSH_EPHEMERAL_OPTS -p ${VM_SSH_PORT:-22} root@"$VM" "sh /tmp/bridge-hosts.sh" || printf '::error:: %s\n' "warning: bridge-hosts execution failed"
  debug_sub_log "=> Bridged"
else
  printf '::warning:: %s\n' "/etc/hosts not found locally; nothing to merge." >&2
  debug_sub_log "Nothing transferred"
fi

# best effort cleanup
rm -f "$BRIDGE_HOSTS_SCRIPT_PATH}" 2>/dev/null || true ; # un-stage as needed (but never error)
unset VM
unset BRIDGE_HOSTS_DATA_PATH
unset BRIDGE_HOSTS_SCRIPT_PATH
unset debug_sub_log || true

# done
exit 0; # always exit 0
