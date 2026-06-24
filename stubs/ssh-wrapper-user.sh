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

# default "safe" ENVs (albeit for ssh less is probably more secure)
ENV_INPUTS="${INPUT_ENVS:-CI_REPO CI_COMMIT_SHA VCS_BRANCH_NAME}"
ENV_INPUTS="$ENV_INPUTS PYTHONUTF8 PYTHONCOERCECLOCALE PYTHONDONTWRITEBYTECODE PYTHON_VERSION"
ENV_INPUTS="$ENV_INPUTS GUEST_USER GUEST_UID"

# helper: conditional diagnostic with message
debug_wrapper_log(){ if [ "${DEBUG:-0}" -eq 1 ]; then printf '::debug::%s\n' "$*" ; fi; }

SAFE_GITHUB_LIST='CI GITHUB_ACTION GITHUB_ACTIONS GITHUB_WORKFLOW GITHUB_WORKSPACE GITHUB_RUN_ATTEMPT GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_JOB GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_REF GITHUB_SHA GITHUB_ACTOR RUNNER_DEBUG';

# Usage: build_sendenv_opts [ENV_INPUTS]
# Returns: prints ssh options like: -o SendEnv=VAR1 -o SendEnv=VAR2 ...
build_sendenv_opts() {
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
	ENV_INPUTS_ARG=${1:-$ENV_INPUTS}
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

SSH_EXIT_CODE=0
# check that the USER_KEY is useable
if [ -n "${USER_KEY:-}" ]; then
	debug_wrapper_log "Checking for SSH Identity" ;
	if [ -e "${USER_KEY}" ] || [ -f "${USER_KEY}.pub" ]; then
		debug_wrapper_log "=> Found ${USER_KEY} on disk." ;
		if [ -r "${USER_KEY}" ]; then
			debug_wrapper_log "..=> Found ${USER_KEY}" ;
		elif [ -f "${USER_KEY}" ] || [ -e "${USER_KEY}.pub" ]; then
			debug_wrapper_log "..=> Found ${USER_KEY}.pub file." ;
			debug_wrapper_log "....=> Trying to apply permission corrections" ;
			# TODO: add -v if in debug mode
			chmod 600 "${USER_KEY}" || SSH_EXIT_CODE=77 ;
			if [ ${SSH_EXIT_CODE} -eq 0 ] && [ -r "${USER_KEY}" ]; then
				debug_wrapper_log "......=> Fixed ${USER_KEY} keyfile" ;
			else
				debug_wrapper_log "....=> Applying corrections Unsuccessful" ;
				SSH_EXIT_CODE=77 ;
			fi ;
		else
			debug_wrapper_log "..=> Missing ${USER_KEY} keyfile" ;
			SSH_EXIT_CODE=66 ;
		fi ;
	else
		debug_wrapper_log "..=> Missing SSH Identity" ;
		SSH_EXIT_CODE=66 ;
	fi ;
fi ;

if [ SSH_EXIT_CODE -eq 0 ]; then
	# Check working directory
	GITHUB_WS="${GITHUB_WORKSPACE:-$PWD}"
	# Build SSH arguments
	SSH_EPHEMERAL_USER_OPTS="" # reset each time to avoid mis-re-use
	SSH_EPHEMERAL_USER_OPTS=$(build_sendenv_opts);
	SSH_EPHEMERAL_USER_OPTS="$SSH_EPHEMERAL_USER_OPTS -o BatchMode=yes -o EscapeChar=none -e none -l ${GUEST_USER}"
	# TODO: ephemerally cache new hosts via:
	# -o UserKnownHostsFile=${ANYVM_SSH_KNOWN_HOSTS_PATH:-/dev/null}
	SSH_EPHEMERAL_USER_OPTS="$SSH_EPHEMERAL_USER_OPTS -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
	ssh $SSH_EPHEMERAL_USER_OPTS -p ${VM_SSH_PORT:-22} -i $USER_KEY "${GUEST_USER:-runner}@${VM_SSH_HOST:-}" "cd \"${GITHUB_WS}\"; $@" ;
	SSH_EXIT_CODE=$?;
fi ;

#cleanup
unset build_sendenv_opts
unset ENV_INPUTS
unset GITHUB_WS
# reset each time to avoid mis-re-use
unset SSH_EPHEMERAL_USER_OPTS
exit ${SSH_EXIT_CODE:-255}
