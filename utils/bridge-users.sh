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
test -x "$(command -v ssh)" || exit 126 ;
test -x "$(command -v ssh-keygen)" || exit 126 ;
test -x "$(command -v openssl)" || exit 126 ;
set -eu

# create_user.sh

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
# TODO: verify ANYVM_CREATE_CI_USER_FILE is set or abort

ANYVM_CREATE_CI_USER_FILE="${ANYVM_CREATE_CI_USER_FILE:-}"
BRIDGE_DATA_DIR="${DATA_DIR:-}"
SSH_EPHEMERAL_OPTS="${SSH_EPHEMERAL_OPTS:-}"
BRIDGE_VM="${VM_SSH_HOST:-127.0.0.1}"
BRIDGE_VM_PORT="${VM_SSH_PORT:-22}"
VM_CI_USER="${GUEST_USER:-runner}"
USER_KEY="${USER_KEY:-}"
EPHEM_KEY_TYPE="${EPHEM_KEY_TYPE:-rsa}"
EPHEM_KEY_BITS="${EPHEM_KEY_BITS:-3072}"

# helper: conditional diagnostic with message
debug_user_log(){ if [ "${DEBUG:-0}" -eq 1 ]; then printf '::debug:: %s\n' "$*"; fi; }

# Portable sh (e.g., FreeBSD /bin/sh) helper:
# Masks the exact strings passed as arguments, using GitHub Actions logging command.
# Usage: mask_inputs "$foo" "$bar"
mask_user_inputs() {
  # Nothing to do if no args
  [ "$#" -eq 0 ] && return 0

  # Guard against GitHub-hosted environment to keep from spraying logs
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0

  # Iterate over all args; each is masked exactly as provided
  while [ "$#" -gt 0 ]; do
    str=$1;
    # Skip empty strings to avoid accidental overbroad masking
    if [ -n "$str" ]; then printf '%s\n' "::add-mask::$str"; fi ;
    shift ;
  done
}

# Usage: build_user_sendenv_opts [ENV_INPUTS]
# Returns: prints ssh options like: -o SendEnv=VAR1 -o SendEnv=VAR2 ...
build_user_sendenv_opts() {
	sendenv_opts=
	# helper: check if a variable name is present in the environment
	env_has() {
		# printf to avoid external env binary in very minimal shells; use 'env' if unavailable
		# This implementation uses 'env' if present, otherwise falls back to /bin/printenv if available.
		if command -v env >/dev/null 2>&1; then
			env | awk -F= '{print $1}' | grep -x -- "$1" >/dev/null 2>&1
		else
			printenv 2>/dev/null | awk -F= '{print $1}' | grep -x -- "$1" >/dev/null 2>&1
		fi
	}

	for gv in $SAFE_GITHUB_LIST; do
		if env_has "$gv"; then
			sendenv_opts="$sendenv_opts -o SendEnv=$gv"
		fi
	done

	# second argument or ENV_INPUTS env var may provide extra names (space-separated)
	ENV_INPUTS_ARG=${1:-${ENV_INPUTS:-}}
	if [ -n "$ENV_INPUTS_ARG" ]; then
		for name in $ENV_INPUTS_ARG; do
			# sanitize to [A-Za-z0-9_]
			name_clean=$(printf '%s' "$name" | sed 's/[^A-Za-z0-9_]//g')
			[ -z "$name_clean" ] && continue
			if env_has "$name_clean"; then
				sendenv_opts="$sendenv_opts -o SendEnv=$name_clean"
			fi
		done
	fi

	# Print result (caller can capture with var=$(build_sendenv_opts) or use eval)
	printf '%s' "$sendenv_opts"
}

# TODO: verify ANYVM_CREATE_CI_USER_FILE is a file that exists
if [ -f "${ANYVM_CREATE_CI_USER_FILE:-}" ]; then
	debug_user_log "Preparing script to clone user on to Guest VM" ;
	CREATE_CI_USER_SCRIPT_PATH="$BRIDGE_DATA_DIR/create_user_$$.sh"
	# TODO: add -v only in debug mode
	cp -f "${ANYVM_CREATE_CI_USER_FILE}" "$CREATE_CI_USER_SCRIPT_PATH"
	debug_user_log "=> Staged" & debug_user_log "..=> Setting Permissions on staged script" ;
	chmod +x "$CREATE_CI_USER_SCRIPT_PATH"

	debug_user_log "Ready to transfer \"${CREATE_CI_USER_SCRIPT_PATH}\" to Guest VM" &

	debug_user_log "Generating VM User keys" ;
	ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$USER_KEY" -N "" -V -1m:+6h -C "${GUEST_USER:-'runner[bot]'}@users.noreply.github.com" >/dev/null || printf "::error title='FAILED'::%s\n" "Failed to generate ephemeral user keys"
	debug_user_log "Checking for new ephemeral user key pair"

	if [ ! -f "$USER_KEY" ] || [ ! -f "$USER_KEY.pub" ]; then
		debug_user_log "=> Can not find new ephemeral user keys"
		printf '::warning:: %s\n' "warning: ephemeral user key pair not found at $USER_KEY / $USER_KEY.pub; Configuring SSH steps WILL fail"
	else
		debug_user_log "=> Found new ephemeral user keys"
		# TODO: check that found keys are indeed a pair
		ssh-keygen -lf "$USER_KEY.pub"
	fi

	USER_PUB_CONTENT="$(cat ${USER_KEY}.pub)"
	mask_user_inputs "$USER_PUB_CONTENT";

	# 4d. copy rotation script and run it using baked key (best-effort)
	if [ -f "$USER_KEY" ]; then
		debug_user_log "=> Waiting for transfer" ;
		USER_PUB_TFILE=$(printf '%s\n' "$RANDOM$RANDOM$RANDOM$RANDOM" | openssl dgst -sha256 - | cut -d\= -f 2-2 | tr -d ' ' | head -n1)
		mask_user_inputs "${USER_PUB_TFILE}";
		debug_user_log "=> Ready to transfer user public key data to Guest VM" ;

		scp $SSH_EPHEMERAL_OPTS -P $BRIDGE_VM_PORT "$CREATE_CI_USER_SCRIPT_PATH" root@"$BRIDGE_VM":/tmp/create_user.sh || printf '::Error:: %s\n' "failed to scp create_user script"
		scp $SSH_EPHEMERAL_OPTS -P $BRIDGE_VM_PORT "${USER_KEY}.pub" root@"$BRIDGE_VM":/tmp/"${USER_PUB_TFILE}" || printf '::Error:: %s\n' "failed to scp create_user data"
		debug_user_log "..=> Transferred" & debug_user_log "..=> Waiting for user sync" &

		ssh $SSH_EPHEMERAL_OPTS -p $BRIDGE_VM_PORT root@"$BRIDGE_VM" "sh /tmp/create_user.sh ${VM_CI_USER} /tmp/${USER_PUB_TFILE};" || printf '::Error:: %s\n' "warning: create_user execution failed" ;
		unset USER_PUB_TFILE ; # TODO: keep this var until /tmp is cleaned-up on guest VM too
		debug_user_log "..=> Synced"
	else
	  printf '::warning:: %s\n' "/etc/hosts not found locally; nothing to do." >&2
	  debug_user_log "Nothing transferred"
	fi

	debug_user_log "=> Attempt to drop root access" &
	SSH_EPHEMERAL_OPTS="";
	unset SSH_EPHEMERAL_OPTS;
	# TODO: deal with root keys more securely

	debug_user_log "=> Will now try ephemeral user key pair"

	SSH_USER_EPHEMERAL_OPTS=$(build_user_sendenv_opts);
	# verify ephemeral works (try a few times)
	SSH_USER_EPHEMERAL_OPTS="$SSH_USER_EPHEMERAL_OPTS -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $USER_KEY -o ConnectTimeout=5"
	u_ok=1
	for _step in 1 2 3; do
		if ssh $SSH_USER_EPHEMERAL_OPTS -p $BRIDGE_VM_PORT -o BatchMode=yes ${VM_CI_USER}@"$BRIDGE_VM" "echo OK" >/dev/null 2>&1; then u_ok=0; break; fi
		sleep ${_step:-1}
	done
	if [ $u_ok -ne 0 ]; then
		printf '::Error:: %s\n' "warning: ephemeral key login failed; continuing with subsequent steps will fail"
	else
		debug_user_log "User and Keys successfully configured"
	fi

	# best effort cleanup
	rm -f "$CREATE_CI_USER_SCRIPT_PATH}" 2>/dev/null || true ; # un-stage as needed (but never error)
fi;
unset BRIDGE_VM
unset BRIDGE_VM_PORT
unset BRIDGE_DATA_DIR
unset CREATE_CI_USER_SCRIPT_PATH
unset VM_CI_USER
unset SSH_USER_EPHEMERAL_OPTS
unset build_user_sendenv_opts || true
unset debug_user_log || true
unset mask_user_inputs || true

# done
exit 0; # always exit 0
