#! /bin/bash
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

# MARK: START
# Get the input path of this script as called
MY_OWN_PATH="$0"
# Remove the trailing slash if present
MY_OWN_PATH="${MY_OWN_PATH%/}"
# Extract the directory name
ANYVM_UTIL_PATH_ARG="${MY_OWN_PATH%/*}"

if [ -d "$ANYVM_UTIL_PATH_ARG" ]; then
	case ":$PATH:" in
		*":$ANYVM_UTIL_PATH_ARG:"*) ;;  # already in PATH
		*) PATH="${PATH:+"$PATH:"}$ANYVM_UTIL_PATH_ARG"; export PATH ;;
	esac
fi

unset MY_OWN_PATH ;
set -eu

# MARK: load functions
. "${ANYVM_UTIL_PATH_ARG:-.}/latest-vm-release.sh" ;
. "${ANYVM_UTIL_PATH_ARG:-.}/expand-path-tilde.sh" ;

# MARK: Inputs
DEBUG=$( [ "${ACTIONS_RUNNER_DEBUG:-}" ] || [ "${ACTIONS_STEP_DEBUG:-}" ] || [ "${INPUT_DEBUG:-}" ] && printf 1 || printf 0 )
ANYVM_OSNAME="${INPUT_OSNAME:-freebsd}"  # freebsd / ghostbsd / openbsd / netbsd / dragonflybsd / midnightbsd / solaris / omnios / openindiana / tribblix / haiku / ubuntu / blissos
ANYVM_RELEASE="${INPUT_RELEASE:-$(get_latest_vm_release $ANYVM_OSNAME)}"
ANYVM_ARCH="${INPUT_ARCH:-}"  # x86_64 / aarch64 / riscv64 / s390x / powerpc64 / ppc64le / sparc64
ANYVM_MEM="${INPUT_MEM:-6144}"  # e.g., default to ((6*1024)*(1024*1024))/(1024*1024) MiB
ANYVM_CPU="${INPUT_CPU:-1}"
ANYVM_CPU_ARCH="${INPUT_CPU_ARCH:-}"  # optional VM specific CPU model
ANYVM_VERSION="${ANYVM_VERSION:-2.1.8}"    # pin this per OS builder
ANYVM_SHA="7d20a921892ad49d4338dc4d9b641b496658cb78"  # v0.4.3
ANYVM_CACHE_DIR="$(expand_tilde "${INPUT_CACHE_DIR:-${RUNNER_TOOL_CACHE:-/opt}/anyvm-cache}")"
INPUT_DATA_DIR="${INPUT_DATA_DIR:-data}"
INPUT_DATA_DIR="$(expand_tilde "$INPUT_DATA_DIR")"
DATA_DIR="${ANYVM_CACHE_DIR}/${INPUT_DATA_DIR}"
VM_USER_CREATE="${INPUT_CREATE_USER:-true}"    # create non-root user by default
HOST_USER="${INPUT_HOST_USER:-${RUNNER_USER:-$(whoami)}}"
GITHUB_TIMEOUT="${INPUT_TIMEOUT:-${JOB_TIMEOUT:-360}}"  # minutes; JOB_TIMEOUT can be set by workflow
ANYVM_USE_VNC="${INPUT_ANYVM_USE_VNC:-false}"
ANYVM_USE_IPV6="${INPUT_USE_IPV6:-false}" # a value of 'true' adds --enable-ipv6 to anyvm args
SYNC_METHOD="${INPUT_SYNC:-scp}"
ANYVM_SYNC_TIME=$( [ "${INPUT_SYNC_TIME:-}" ] && printf 1 || printf 0 )
COPYBACK="${INPUT_COPYBACK:-true}"
ENV_INPUTS="${INPUT_ENVS:-}"
ANYVM_TOOL_CACHE_SUB_DIR="/anyvm-in-ci/bin"
VMSH_DIR="${RUNNER_TOOL_CACHE:-/opt}${ANYVM_TOOL_CACHE_SUB_DIR:-}"
VMSH_CMD_NAME="${INPUT_CUSTOM_SHELL_NAME:-vmsh.sh}"
VMSH_CMD="${VMSH_DIR:-}/${VMSH_CMD_NAME:-}"
EPHEM_KEY_TYPE="rsa"
EPHEM_KEY_BITS=3072

# TODO: carefully resolve relative path to a canonical path
ANYVM_ROTATE_RKEYS_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/rotate_root_keys.sh" ;
ANYVM_BRIDGE_HOSTS_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/bridge-hosts-stub.sh" ;
ANYVM_CREATE_CI_USER_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/create_user.sh" ;
ANYVM_WRAP_USER_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/ssh-wrapper-user.sh" ;
ANYVM_WRAP_ROOT_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/ssh-wrapper-root.sh" ;

# More Vars
# override this flag to disable re-downloading anyvm.py ("1" when cached)
ANYVM_PY_IN_CACHE=0
ANYVM_NAME_SUFFIX=""
SAFE_GITHUB_LIST='GITHUB_ACTION GITHUB_ACTIONS GITHUB_WORKFLOW GITHUB_RUN_ATTEMPT GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_JOB GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_REF GITHUB_SHA GITHUB_ACTOR RUNNER_DEBUG DEBUG'
export SAFE_GITHUB_LIST

# Path to anyvm.py command (path not-resolved -- may need to create path for cache)
ANYVM_PY_PATH="$ANYVM_CACHE_DIR/anyvm.py"
# TODO: leverage GITHUB_SERVER here (for GHES)
ANYVM_URL="https://raw.githubusercontent.com/anyvm-org/anyvm/${ANYVM_SHA}/anyvm.py"
ANYVM_RELEASE_TAG="v${ANYVM_VERSION}"
RB_OWNER="anyvm-org"
RB_REPO="${ANYVM_OSNAME}-builder"
# TODO: leverage GITHUB_SERVER here (for GHES)
BASE_URL="https://github.com/${RB_OWNER}/${RB_REPO}/releases/download/${ANYVM_RELEASE_TAG}"

ANYVM_NAME_SUFFIX=""

# MARK: Functions

# helper: conditional diagnostic with message
debug_log(){ if [ "${DEBUG:-0}" -eq "1" ]; then printf '::debug:: %s\n' "$*"; fi; }

debug_log "Defining shell helper functions" ;
debug_log "=> Defining error handling function" &

# helper: fail with message
die(){ printf "::error file='%s',title='ERROR':: %s\n" "${0}" "$*" >&2; exit 1; }

debug_log "=> Defining safe uuidgen function" &
# helper: portable uuidgen
safe_uuidgen() {
	if command -v uuidgen >/dev/null 2>&1; then
		uuidgen
	else
		printf "%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n" $RANDOM $RANDOM $RANDOM $(($RANDOM & 0x0fff | 0x4000)) $(($RANDOM & 0x3fff | 0x8000)) $RANDOM $RANDOM $RANDOM
	fi
}

debug_log "=> Defining string matches function" &

# helper: is the string a match or not (usage: if matches str1 str2; then ... ; else .... ; fi)
matches(){
	case "$1" in
		${2}) return 0 ;;     # llvm-ar friendly format
		*) false ;;
	esac
}

debug_log "=> Defining GitHub log masking function" &

# Portable sh (e.g., FreeBSD /bin/sh) helper:
# Masks the exact strings passed as arguments, using GitHub Actions logging command.
# Usage: mask_inputs "$foo" "$bar"
mask_inputs() {
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

debug_log "=> Defining GitHub QEMU installer function" &

install_qemu(){
	printf "::group::%s\n" "Setup-QEMU" ;
	if command -v qemu-system-x86_64 >/dev/null 2>&1; then
		printf '%s\n' "qemu present"
		return
	fi
	case "$(uname -s)" in
		Linux)
			if command -v apt-get >/dev/null 2>&1; then
			# TODO: tailor the install to the required for target VM arch
				sudo apt-get update && sudo apt-get install --no-install-recommends -y \
					zstd ovmf xz-utils qemu-utils ca-certificates \
					qemu-system-x86 qemu-system-arm qemu-efi-aarch64 \
					qemu-efi-riscv64 qemu-system-riscv64 qemu-system-misc u-boot-qemu \
					qemu-system-ppc qemu-system-s390x qemu-system-sparc \
					openssh-client || die "failed to install qemu via apt-get"
			elif command -v yum >/dev/null 2>&1; then
				printf '%s\n' "Unsupported runner OS"
				sudo yum install -y qemu-kvm qemu-img || die "failed to install qemu via yum"
			fi
			;;
		Darwin)
			if command -v brew >/dev/null 2>&1; then
				# TODO: set other hombrew vars like HOMEBREW_NO_ANALYTICS when cache mode is disabled
				# TODO: set other hombrew vars when cache mode is enabled (and configure GHA cache for brew)
				if [ "${DEBUG}" -eq 1 ]; then export HOMEBREW_VERBOSE=${DEBUG}; else export HOMEBREW_NO_ENV_HINTS=1; fi ;
				export HOMEBREW_NO_INSECURE_REDIRECT=1;  # forbid redirects from secure HTTPS to insecure HTTP
				HOMEBREW_GITHUB_API_TOKEN="${ANYVM_TOKEN:-${GH_TOKEN:-}}" brew install qemu || die "failed to install qemu via homebrew" ;
				unset HOMEBREW_GITHUB_API_TOKEN ;
			else
				die "Homebrew required on macOS to install qemu"
			fi
			;;
		MINGW*|MSYS*|CYGWIN*)
			if command -v choco >/dev/null 2>&1; then
				choco install qemu -y || die "failed to install qemu via choco"
			fi
			;;
		*)
			die "Unsupported runner OS"
			;;
	esac
	printf "::endgroup::\n" ;
}

debug_log "=> Defining download function" &

download_file(){
	url=$1 dest=$2
	tmp="${dest}.tmp.$(safe_uuidgen)"
	mkdir -p "$(dirname "$dest")" || true
	if ! curl -L --fail --silent --show-error --output "$tmp" --write-out "%{http_code}" --url "$url" >"$tmp.httpcode"; then
		rm -f "$tmp" "$tmp.httpcode"; return 1
	fi
	code="$(cat "$tmp.httpcode" 2>/dev/null || echo "")"; rm -f "$tmp.httpcode"
	[ "$code" = "200" ] || { rm -f "$tmp"; return 2; }
	mv "$tmp" "$dest"; return 0
}

debug_log "=> Defining VM SSH health check function" &

wait_for_ssh(){ local h=$1 p=$2 t=${3:-180}; local s; s=$(date +%s); if command -v nc >/dev/null 2>&1; then
	while ! nc -z "$h" "$p"; do sleep 1; if [ $(( $(date +%s)-s )) -gt "$t" ]; then return 1; fi; done
else
	while ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$p" -o BatchMode=yes -o EscapeChar=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null "$h" true 2>/dev/null; do
		sleep 1
		if [ $(( $(date +%s)-s )) -gt "$t" ]; then return 1; fi
	done
fi
}

debug_log "=> Defining ssh env helper" ;

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

debug_log "=> Defined" ;
# MARK: Checks
debug_log "Checking for Required tools" ;

# 0. minimal required tools
required=(python3 curl cut git openssl ssh scp ssh-keygen tr date mktemp chmod mkdir sed awk)
for cmd in "${required[@]}"; do
	debug_log "=> Checking for \"$cmd\"" ;
	if ! command -v "$cmd" >/dev/null 2>&1; then
		die "required command not found: $cmd" ;
	else
		debug_log "=> Found \"$cmd\" at "$(command -v "$cmd" 2>&1);
	fi ;
done

debug_log "Ensure cache dirs exists" &

for SOME_CACHE_DIR in "$ANYVM_CACHE_DIR" "$DATA_DIR" "$DATA_DIR/images" "${VMSH_DIR}"; do
	mkdir -p "$SOME_CACHE_DIR" ;
	debug_log "=> Checking for \"$SOME_CACHE_DIR\"" ;
	if [ -d "$SOME_CACHE_DIR" ]; then
		debug_log "=> Found \"$SOME_CACHE_DIR\"" ;
	else
		die "Required directory could not be created correctly: $SOME_CACHE_DIR" ;
	fi ;
done

# optional tools: rsync brew apt-get yum choco etc.

debug_log "Checking for qemu tools" ;
# 1. Install QEMU (minimal cross-platform approach)
install_qemu

debug_log "=> qemu installed" &

# 2. fetch anyvm from github and use its anyvm.py

debug_log "Ensure we have anyvm.py..."
# Download anyvm.py (kept)

if [ -n "${ANYVM_CACHE_DIR:-}" ] && [ ! -f "${ANYVM_PY_PATH:-}" ]; then
	debug_log "=> anyvm.py not found in cache"
	ANYVM_PY_IN_CACHE=0;
elif [ -n "${ANYVM_CACHE_DIR:-}" ]; then
	debug_log "=> anyvm.py found (cached)"
	ANYVM_PY_IN_CACHE=1;
	# TODO: leverage cache here
else
	debug_log "=> but cache is disabled or not available"
	ANYVM_PY_IN_CACHE=0;
fi

if [ -n "${ANYVM_PY_IN_CACHE}" ] || [ "${ANYVM_PY_IN_CACHE}" -ne 1 ] ; then
	debug_log "=> must download anyvm.py" &
	download_file "$ANYVM_URL" "$ANYVM_PY_PATH" || die "failed to download anyvm.py"
	debug_log "download anyvm.py"
else
	# leverage cache here
	debug_log "=> Will use cached path: \"${ANYVM_PY_PATH:-}\""
fi

# TODO: add conditional check here
chmod +x "$ANYVM_PY_PATH" || true

# 2b. at this point we can expect a working anyvm.py tool
# Path to anyvm.py command (path resolved
ANYVM_BIN="$ANYVM_PY_PATH"

# MARK: Speculative Pre-cacheing

# 2c. (prep) Pre-cache Speculative "needed" resources locally
debug_log "Determining Builder ${BASE_URL:-'null'}"
if [ -n "$ANYVM_ARCH" ]; then
	case "${ANYVM_ARCH}" in
		x86_64)
			;;
		*)
			ANYVM_NAME_SUFFIX="-${ANYVM_ARCH}"
			;;
	esac
fi
ANYVM_NAME="${ANYVM_OSNAME}-${ANYVM_RELEASE}${ANYVM_NAME_SUFFIX}"
debug_log "Requesting target ${ANYVM_NAME:-}"

# 2c. (work) Try image extensions (preferred order)
IMAGE_PATH=""
for ext in "qcow2.zst" "qemu"; do
	cand="$DATA_DIR/images/${ANYVM_NAME}.${ext}"
	url="${BASE_URL}/${ANYVM_NAME}.${ext}"
	debug_log "Fetching target from ${url}"
	if download_file "$url" "$cand"; then
		if [ -n "${IMAGE_PATH}" ] && [ -f "${IMAGE_PATH}" ]; then
			continue ;
		else
			IMAGE_PATH="$cand"; chmod 644 "$IMAGE_PATH" || true;
		fi ;
	fi ;
done ;
[ -n "$IMAGE_PATH" ] || die "no image found for ${ANYVM_NAME} (.qcow2.zst nor .qemu) in ${DATA_DIR}/images"

# 2d. Fetch (Speculatively "needed") baked-in key-pair for guest VM
BAKED_PUB="$DATA_DIR/${ANYVM_NAME}.pub"
BAKED_PRIV="$DATA_DIR/${ANYVM_NAME}"
# URLs for baked keys: .pub (public) and .id_rsa (private)
PUB_URL="${BASE_URL}/${ANYVM_NAME}-id_rsa.pub"
PRIV_URL="${BASE_URL}/${ANYVM_NAME}-host.id_rsa"

if ! download_file "$PUB_URL" "$BAKED_PUB"; then
	printf '%s\n' "warning: failed to download baked pubkey from $PUB_URL"; rm -f "$BAKED_PUB"
else chmod 644 "$BAKED_PUB" || true; fi

if ! download_file "$PRIV_URL" "$BAKED_PRIV"; then
	printf '%s\n' "warning: failed to download baked private key from $PRIV_URL"; rm -f "$BAKED_PRIV"
else chmod 600 "$BAKED_PRIV" || true; fi

if [ ! -f "$BAKED_PRIV" ] || [ ! -f "$BAKED_PUB" ]; then
	printf '%s\n' "warning: baked key pair not found at $BAKED_PRIV / $BAKED_PUB; initial SSH steps WILL fail"
fi

{ BAKED_PUB_CONTENT=$(cat <"$BAKED_PUB");
	mask_inputs "$BAKED_PUB_CONTENT";
	unset BAKED_PUB_CONTENT ;
	# "shred" the var
	BAKED_PUB_CONTENT="<NULL>" ;
	unset BAKED_PUB_CONTENT ;} 2>/dev/null || true ; # pub-key is only best effort


#export IMAGE_PATH
#printf '%s\n' "Image downloaded to $IMAGE_PATH"

# TODO: dynamically use --qcow2 when cached

# 3. start VM
# TODO: need way to use pid file eg --pidfile "$DATA_DIR/anyvm.pid"
debug_log "Configuring ANYVM call"
debug_log "=> Selecting VM OS (--os \"${ANYVM_OSNAME}\")" &
debug_log "=> Selecting VM RAM (--mem \"${ANYVM_MEM}\")" &
debug_log "=> Selecting VM Builder (--builder \"${ANYVM_VERSION}\")" &
START_ARGS=(--os "${ANYVM_OSNAME}" --mem "$ANYVM_MEM" --detach --builder "$ANYVM_VERSION")
if [ -d "${DATA_DIR:-}" ]; then
	debug_log "=> Selecting data dir (--data-dir \"$INPUT_DATA_DIR\")"
	START_ARGS+=(--data-dir "$DATA_DIR")
fi
if [ -n "$ANYVM_ARCH" ] ; then
	debug_log "=> Selecting VM ISA (--arch \"${ANYVM_ARCH}\")"
	START_ARGS+=(--arch "${ANYVM_ARCH}")
fi
if [ -n "$ANYVM_CPU_ARCH" ] ; then
	debug_log "=> Selecting VM CPU Model Emulation (--cpu-type \"${ANYVM_CPU_ARCH}\")"
	START_ARGS+=(--cpu-type "${ANYVM_CPU_ARCH}")
fi

if [ -n "$ANYVM_RELEASE" ] ; then
	debug_log "=> Selecting VM Release (--release \"${ANYVM_RELEASE}\")"
	START_ARGS+=(--release "${ANYVM_RELEASE}")
fi
# with fixed CPU count
if [ -n "$ANYVM_CPU" ] && [ "${ANYVM_CPU}" -ge 1 ]; then
	debug_log "=> Selecting VM CPU count (--cpu \"${ANYVM_CPU}\")"
	START_ARGS+=(--cpu "${ANYVM_CPU}")
fi

# with ipv6 support
if matches "$ANYVM_USE_IPV6" "true"; then
	debug_log "=> Selecting VM RFC 8200: STD 86 Networking mode (--enable-ipv6)"
	START_ARGS+=(--enable-ipv6)
else
	debug_log "=> Selecting VM RFC 791: STD 5 Networking mode (default)"
fi

# with VNC disabled (CI focused)
if matches "$ANYVM_USE_VNC" "true" ; then
	printf "::warning file='%s',title='EXPOSED':: %s\n" "${0}" "VM's VNC is exposed. This is not recommended in a CI/CD environment!"
else
	debug_log "=> Disabling VNC in CI pipeline for improved security (--vnc off)"
	START_ARGS+=(--vnc off)
fi

VM_SSH_HOST="127.0.0.1"
debug_log "=> Limiting VM SSH to localhost in CI pipeline for improved security (\"$VM_SSH_HOST\")"

# get port robustly, default to 55555
VM_SSH_PORT=$(sh -c 'awk -v L=49154 -v H=64535 "BEGIN{srand(); print int(L+rand()*(H-L+1))}"')
VM_SSH_PORT="${VM_SSH_PORT:-55555}"
debug_log "=> Selecting VM SSH port (--ssh-port \"$VM_SSH_PORT\")"
START_ARGS+=(--ssh-port "${VM_SSH_PORT}")

# TODO: make this more flexible via overrides and relative default
# HEURISTIC abort after 1/100th (1%) of step max timeout
# --boot-timeout-sec ( (($GITHUB_TIMEOUT * 60) / 100) )
printf "::group::%s\n" "Start-ANYVM" ;

debug_log "Starting ANYVM with args: ${START_ARGS[@]}" ;

python3 "$ANYVM_BIN" "${START_ARGS[@]}" ;

debug_log "=> Waiting for Guest VM to become available"

# wait_for_ssh: use nc if present, otherwise attempt ssh -o BatchMode test
wait_for_ssh "$VM_SSH_HOST" "$VM_SSH_PORT" 360 || die "SSH did not become available on $VM_SSH_HOST:$VM_SSH_PORT"

debug_log "Guest VM became available (on $VM_SSH_HOST:$VM_SSH_PORT)" ;

printf "::endgroup::\n";

debug_log "Refreshing VM keys" ;
# 4. RSA-3072 ephemeral key generation with expiry comment
# TODO: don't use date (birthday-weakness)
EPHEM_KEY="${HOME:-.}/id_ci_vm_ephemeral_$(safe_uuidgen)_rsa"
ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$EPHEM_KEY" -N "" -V -1m:+6h -C "ci-vm-ephemeral-$(date -u +%s)" >/dev/null || die "Failed to generate ephemeral keys"

debug_log "Checking for new ephemeral key pair"

if [ ! -f "$EPHEM_KEY" ] || [ ! -f "$EPHEM_KEY.pub" ]; then
	debug_log "=> Can not find new ephemeral keys"
	printf '%s\n' "warning: ephemeral key pair not found at $EPHEM_KEY / $EPHEM_KEY.pub; Rotating SSH steps WILL fail"
else
	debug_log "=> Found new ephemeral keys"
	# TODO: check that found keys are indeed a pair
	ssh-keygen -lf "$EPHEM_KEY.pub"
fi

# compute expiry timestamp (store in comment or file if needed)
# EXP_TS=$(( $(date +%s) + "$GITHUB_TIMEOUT" ))

# 4b. prepare env export script for the VM: gather non-sensitive GITHUB_* and INPUT_ENVS

# 4c. rotation: replace all users' authorized_keys (root) with ephemeral pubkey — safer atomic replace
EPHEM_PUB_CONTENT="$(cat ${EPHEM_KEY}.pub)"
mask_inputs "$EPHEM_PUB_CONTENT";

debug_log "..=> Preparing script to rotate Guest VM keys" ;
ROTATE_ROOT_SCRIPT_PATH="$DATA_DIR/rotate_root_$(safe_uuidgen).sh"
# TODO: only add -v when in debug mode
cp -f "${ANYVM_ROTATE_RKEYS_FILE}" "$ROTATE_ROOT_SCRIPT_PATH"
debug_log "..=> Staged" & debug_log "....=> Setting Permissions on staged script" ;
chmod +x "$ROTATE_ROOT_SCRIPT_PATH"

debug_log "....=> Ready to transfer \"${ROTATE_ROOT_SCRIPT_PATH}\" to Guest VM" ;

# 4d. copy rotation script and run it using baked key (best-effort)
if [ -f "$BAKED_PRIV" ]; then
	SSH_BAKED_OPTS=$(build_sendenv_opts);
	SSH_BAKED_OPTS="$SSH_BAKED_OPTS -o BatchMode=yes -o EscapeChar=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $BAKED_PRIV"
	debug_log "......=> Waiting for transfer" ;
	EPHEM_PUB_TFILE=$(printf '%s\n' "$RANDOM$RANDOM$RANDOM$RANDOM" | openssl dgst -sha256 - | cut -d\= -f 2-2 | tr -d ' ' | head -n1)
	mask_inputs "${EPHEM_PUB_TFILE}";
	scp $SSH_BAKED_OPTS -P $VM_SSH_PORT "$ROTATE_ROOT_SCRIPT_PATH" root@"$VM_SSH_HOST":/tmp/rotate_root.sh || die "failed to scp rotate_root script"
	scp $SSH_BAKED_OPTS -P $VM_SSH_PORT "${EPHEM_KEY}.pub" root@"$VM_SSH_HOST":/tmp/"${EPHEM_PUB_TFILE}" || die "failed to scp rotate_root data"

	# TODO: cleanup local script copy once transferred
	debug_log "....=> Transferred" & debug_log "..=> Waiting for rotation" ;
	ssh $SSH_BAKED_OPTS -p $VM_SSH_PORT root@"$VM_SSH_HOST" "sh /tmp/rotate_root.sh /tmp/${EPHEM_PUB_TFILE};" || die "warning: rotate_root execution failed" ;
	unset EPHEM_PUB_TFILE ; # TODO: keep this var until /tmp is cleaned-up on guest VM too
	debug_log "..=> Rotated"
else
	die "warning: baked private key not available; cannot run remote rotation via baked key"
fi

debug_log "=> Will now try ephemeral key pair"

SSH_EPHEMERAL_OPTS=$(build_sendenv_opts);
# verify ephemeral works (try a few times)
SSH_EPHEMERAL_OPTS="$SSH_EPHEMERAL_OPTS -o BatchMode=yes -o EscapeChar=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $EPHEM_KEY -o ConnectTimeout=5"
ok=1
for _step in 1 2 3; do
	if ssh $SSH_EPHEMERAL_OPTS -p $VM_SSH_PORT -o BatchMode=yes root@"$VM_SSH_HOST" "echo OK" >/dev/null 2>&1; then ok=0; break; fi
	sleep 1
done
if [ $ok -ne 0 ]; then
	die "warning: ephemeral key login failed; continuing with subsequent steps will fail"
else
	debug_log "Keys successfully rotated"
fi

# 4e. copy host /etc/hosts to guest (temp file) - best-effort
debug_log "Bridging host file to guest"
if [ -x "${ANYVM_UTIL_PATH_ARG}/bridge-hosts.sh" ]; then
	debug_log "=> Bridging via util: bridge-hosts.sh"
	ANYVM_BRIDGE_HOSTS_FILE="${ANYVM_BRIDGE_HOSTS_FILE}" DATA_DIR="${DATA_DIR}" SSH_EPHEMERAL_OPTS="${SSH_EPHEMERAL_OPTS}" VM_SSH_HOST="${VM_SSH_HOST}" VM_SSH_PORT="${VM_SSH_PORT}" DEBUG="${DEBUG:-}" \
	"${ANYVM_UTIL_PATH_ARG}/bridge-hosts.sh"
else
	# best-effort fallback
	debug_log "=> Bridging via root"
	scp $SSH_EPHEMERAL_OPTS -P $VM_SSH_PORT /etc/hosts root@"$VM_SSH_HOST":/tmp/hosts.guest || die "failed to scp runner host file script"
	ssh $SSH_EPHEMERAL_OPTS -p $VM_SSH_PORT root@"$VM_SSH_HOST" "cat /tmp/hosts.guest >> /etc/hosts || true" || die "failed to clobber Guest /etc/hosts"
fi

debug_log "Bridging done"

# 4f. optionally create unprivileged user matching host and set its authorized_keys to its own ephemeral key
if matches "$VM_USER_CREATE" "true"; then
	GUEST_USER="${HOST_USER:-runner}"
	USER_KEY="${HOME:-.}/id_user_ci_$(safe_uuidgen)_rsa"
	# TODO: match the UID of GUEST_USER
	debug_log "Cloning CI user to guest VM"
	if [ -x "${ANYVM_UTIL_PATH_ARG}/bridge-users.sh" ]; then
		USER_KEY="${USER_KEY}" GUEST_USER="${GUEST_USER:-runner}" GUEST_UID="${GUEST_UID:-}" DATA_DIR="${DATA_DIR}" ANYVM_CREATE_CI_USER_FILE="${ANYVM_CREATE_CI_USER_FILE}" SSH_EPHEMERAL_OPTS="$SSH_EPHEMERAL_OPTS" VM_SSH_HOST="$VM_SSH_HOST" VM_SSH_PORT="$VM_SSH_PORT" DEBUG="${DEBUG:-${RUNNER_DEBUG:-}}" \
		"${ANYVM_UTIL_PATH_ARG}/bridge-users.sh"
	fi
	# TODO: choose a consistent term: synced or cloned or bridged
	debug_log "CI user cloned to guest"

	# set wrapper to use unpriv user key by default and use sudo for privileged ops
	debug_log "..=> Preparing script to run commands on Guest VM" ;
	# TODO: modify script to auto-find specific USER_KEY path (make script targeted but ephemeral)
	# The current issue is in the edge-case of two instances on the same runner, the script could
	# require the caller to manage the USER_KEY var to correctly use the wrapper, that is not ideal.
	cp -f "${ANYVM_WRAP_USER_FILE}" "${VMSH_CMD}"
	debug_log "..=> Staged" & debug_log "....=> Setting Permissions on staged script" ;
	chmod +x "${VMSH_CMD}"
else
	# wrapper uses root ephemeral key
	debug_log "..=> Preparing script to run commands on Guest VM" ;
	# TODO: modify script to auto-find specific USER_KEY path (make script targeted but ephemeral)
	# The current issue is in the edge-case of two instances on the same runner, the script could
	# require the caller to manage the USER_KEY var to correctly use the wrapper, that is not ideal.
	cp -f "${ANYVM_WRAP_ROOT_FILE}" "${VMSH_CMD}"
	debug_log "..=> Staged" & debug_log "....=> Setting Permissions on staged script" ;
	chmod +x "${VMSH_CMD}"
fi

if [ -d "${VMSH_DIR:-}" ]; then
	case ":$PATH:" in
		*":$VMSH_DIR:"*) ;;  # already in PATH
		*) PATH="${PATH:+"$PATH:"}$VMSH_DIR"; export PATH ;;
	esac
fi

debug_log "Bootstrap done"

# MARK: REPLICATE GH workspace
# 6. recreate full GITHUB_WORKSPACE path and rsync content
GITHUB_WS="${GITHUB_WORKSPACE:-$PWD}"

debug_log "Replicating ${GITHUB_WS} to Guest VM"

# ensure destination exists and owned by guest user if present
ssh ${SSH_EPHEMERAL_OPTS} -p $VM_SSH_PORT root@${VM_SSH_HOST} "mkdir -p '$GITHUB_WS' && chown -R '${GUEST_USER}:${GUEST_USER}' '$GITHUB_WS'" || true
if matches "$SYNC_METHOD" "rsync"; then
	GUEST_RSYNC_USER="${GUEST_USER:-runner}"
	RSYNC_KEY="${USER_KEY:-$EPHEM_KEY}"
	RSYNC_EPHEMERAL_OPTS=$(build_sendenv_opts);
	RSYNC_EPHEMERAL_OPTS="$RSYNC_EPHEMERAL_OPTS -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $RSYNC_KEY -o ConnectTimeout=35"
	rsync -a --delete -e "ssh ${RSYNC_EPHEMERAL_OPTS} -p $VM_SSH_PORT" "$GITHUB_WS/" "${GUEST_RSYNC_USER}@${VM_SSH_HOST}:$GITHUB_WS/"
	ssh $SSH_EPHEMERAL_OPTS -p $VM_SSH_PORT root@${VM_SSH_HOST} "chown -R '${GUEST_RSYNC_USER}:${GUEST_RSYNC_USER}' '$GITHUB_WS'" || true
else
	# Use trailing slash and /* glob to copy contents, not the directory itself
	scp -r -P "$VM_SSH_PORT" -i "${EPHEM_KEY}" $SSH_EPHEMERAL_OPTS "$GITHUB_WS"/* "root@${VM_SSH_HOST}:$GITHUB_WS/"
	ssh $SSH_EPHEMERAL_OPTS -p $VM_SSH_PORT root@${VM_SSH_HOST} "chown -R '${GUEST_USER}:${GUEST_USER}' '$GITHUB_WS'" || true
fi

debug_log "=> Replicated"

# MARK: HERE
# 7. run startup hook if exists
"${VMSH_CMD}" $"[ -x ./startup.sh ] && ./startup.sh || true" || true

# 8. run 'prepare' if provided
if [ -n "${INPUT_PREPARE:-}" ]; then
	printf "::group::%s\n" "Run prepare" ;
	"${VMSH_CMD}" "$INPUT_PREPARE" ;
	printf "\n::endgroup::\n" ;
fi

# 9. run CI command (required)
if [ -n "${INPUT_RUN:-}" ]; then
	printf "::group::%s\n" "Run step on VM" ;
	"${VMSH_CMD}" "$INPUT_RUN" ;
	printf "\n::endgroup::\n" ;
fi

# 10. optional copyback logic
if matches "$SYNC_METHOD" "rsync"; then
	rsync -a --delete -e "ssh -p $VM_SSH_PORT -i ${RSYNC_KEY} -o BatchMode=yes -o EscapeChar=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "${GUEST_RSYNC_USER}@${VM_SSH_HOST}:$GITHUB_WS/" "$GITHUB_WS/"
else
	# Use trailing slash and /* glob to copy contents, not the directory itself
	scp -r -P "$VM_SSH_PORT" -i "${RSYNC_KEY}" $SSH_EPHEMERAL_OPTS "root@${VM_SSH_HOST}:$GITHUB_WS/*" "$GITHUB_WS/"
fi


# 10b afterwards
if [ -n "${INPUT_AFTERWARDS:-}" ]; then
	printf "::group::%s\n" "Run afterwards" ;
	"${VMSH_CMD}" "$INPUT_AFTERWARDS" ;
	printf "\n::endgroup::\n" ;
fi

# 11. stop VM and cleanup
if [ -f "$DATA_DIR/anyvm.pid" ]; then
	kill "$(cat "$DATA_DIR/anyvm.pid")" 2>/dev/null || true; rm -f "$DATA_DIR/anyvm.pid"
fi

# shred keys if shred exists, else rm
if command -v shred >/dev/null 2>&1; then
	shred -u "${EPHEM_KEY}" || rm -f "${EPHEM_KEY}"
	[ -n "${USER_KEY:-}" ] && (shred -u "${USER_KEY}" || rm -f "${USER_KEY}")
else
	rm -f "${EPHEM_KEY}"
	[ -n "${USER_KEY:-}" ] && rm -f "${USER_KEY}"
fi
[ -n "${ROTATE_ROOT_SCRIPT_PATH:-}" ] && rm -f "$ROTATE_ROOT_SCRIPT_PATH" || true

# MARK: END
printf "Done\n" ;
