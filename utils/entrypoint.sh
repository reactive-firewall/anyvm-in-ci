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

# load functions
. "${ANYVM_UTIL_PATH_ARG:-.}/latest-vm-release.sh" ;

# Inputs
DEBUG=$( [ "${ACTIONS_RUNNER_DEBUG:-}" ] || [ "${ACTIONS_STEP_DEBUG:-}" ] || [ "${INPUT_DEBUG:-}" ] && printf 1 || printf 0 )
ANYVM_OSNAME="${INPUT_OSNAME:-freebsd}"  # freebsd / ghostbsd / openbsd / netbsd / dragonflybsd / midnightbsd / solaris / omnios / openindiana / tribblix / haiku / ubuntu / blissos
ANYVM_RELEASE="${INPUT_RELEASE:-$(get_latest_vm_release $ANYVM_OSNAME)}"
ANYVM_ARCH="${INPUT_ARCH:-}"  # x86_64 / aarch64 / riscv64 / s390x / powerpc64 / ppc64le / sparc64
ANYVM_MEM="${INPUT_MEM:-6144}"  # e.g., default to ((6*1024)*(1024*1024))/(1024*1024) MiB
ANYVM_CPU="${INPUT_CPU:-1}"
ANYVM_CPU_ARCH="${INPUT_CPU_ARCH:-}"  # optional VM specific CPU model
ANYVM_VERSION="${ANYVM_VERSION:-2.1.8}"    # pin this per OS builder
ANYVM_SHA="7d20a921892ad49d4338dc4d9b641b496658cb78"  # v0.4.3
ANYVM_CACHE_DIR="${INPUT_CACHE_DIR:-${RUNNER_TEMP:-/tmp}/anyvm-cache}"
DATA_DIR="${INPUT_DATA_DIR:-$ANYVM_CACHE_DIR/data}"
VM_USER_CREATE="${INPUT_CREATE_USER:-true}"    # create non-root user by default
HOST_USER="${INPUT_HOST_USER:-${RUNNER_USER:-$(whoami)}}"
GITHUB_TIMEOUT="${INPUT_TIMEOUT:-${JOB_TIMEOUT:-360}}"  # minutes; JOB_TIMEOUT can be set by workflow
ANYVM_USE_VNC="${INPUT_ANYVM_USE_VNC:-false}"
ANYVM_USE_IPV6="${INPUT_USE_IPV6:-false}" # adds --enable-ipv6
SYNC_METHOD="${INPUT_SYNC:-scp}"
COPYBACK="${INPUT_COPYBACK:-true}"
ENV_INPUTS="${INPUT_ENVS:-}"
VMSH_CMD="${INPUT_CUSTOM_SHELL_NAME:-vmsh.sh}"
EPHEM_KEY_TYPE="rsa"
EPHEM_KEY_BITS=3072

# helper: conditional diagnostic with message
debug_log(){ if [ ${DEBUG} ]; then printf '::debug:: %s\n' "$*" >&2; fi; }

# helper: fail with message
die(){ printf "::error file='%s',title='ERROR':: %s\n" "${0}" "$*" >&2; exit 1; }

# helper: is the string a match or not (usage: if matches str1 str2; then ... ; else .... ; fi)
matches(){
  case "$1" in
    ${2}) return 0 ;;     # llvm-ar friendly format
    *) false ;;
  esac
}

# 0. minimal required tools
required=(python3 curl git ssh scp ssh-keygen date mktemp chmod mkdir sed awk)
for cmd in "${required[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "required command not found: $cmd"
  fi
done

debug_log "Ensure cache dirs exists"
mkdir -p "$ANYVM_CACHE_DIR" "$DATA_DIR"

# optional tools: rsync brew apt-get yum choco

# 1. Install QEMU (minimal cross-platform approach)
install_qemu(){
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
        HOMEBREW_GITHUB_API_TOKEN=${ANYVM_TOKEN:-${GH_TOKEN:-}} ;
        # TODO: set other hombrew vars like HOMEBREW_NO_ANALYTICS when cache mode is disabled
        if [ ${DEBUG} ]; then HOMEBREW_VERBOSE=1; fi ;
        HOMEBREW_NO_INSECURE_REDIRECT=1;  # forbid redirects from secure HTTPS to insecure HTTP
        brew install qemu ;
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
}
install_qemu

debug_log "qemu installed"

# 2. fetch anyvm from github and use its anyvm.py
download_file(){
  url=$1 dest=$2 tmp="${dest}.tmp.$$"
  mkdir -p "$(dirname "$dest")" || true
  if ! curl -L --fail --silent --show-error --output "$tmp" --write-out "%{http_code}" --url "$url" >"$tmp.httpcode"; then
    rm -f "$tmp" "$tmp.httpcode"; return 1
  fi
  code="$(cat "$tmp.httpcode" 2>/dev/null || echo "")"; rm -f "$tmp.httpcode"
  [ "$code" = "200" ] || { rm -f "$tmp"; return 2; }
  mv "$tmp" "$dest"; return 0
}

debug_log "Ensure image cache dir exists"
mkdir -p "$DATA_DIR/images"

# TODO: carefully resolve relative path to a canonical path
ANYVM_ROTATE_RKEYS_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/rotate_root_keys.sh" ;
ANYVM_BRIDGE_HOSTS_FILE="${ANYVM_UTIL_PATH_ARG:-.}/../stubs/bridge-hosts-stub.sh" ;

debug_log "Ensure we have anyvm.py"
# Download anyvm.py (kept)
ANYVM_PY_PATH="$ANYVM_CACHE_DIR/anyvm.py"

# TODO: leverage cache here
ANYVM_URL="https://raw.githubusercontent.com/anyvm-org/anyvm/${ANYVM_SHA}/anyvm.py"
download_file "$ANYVM_URL" "$ANYVM_PY_PATH" || die "failed to download anyvm.py"
debug_log "download anyvm.py"
chmod +x "$ANYVM_PY_PATH" || true

# 2b. at this point we can expect a working anyvm.py tool
ANYVM_BIN="$ANYVM_PY_PATH"

# 2c. (prep) Pre-cache Speculative "needed" resources locally
ANYVM_NAME_SUFFIX=""
ANYVM_RELEASE_TAG="v${ANYVM_VERSION}"
RB_OWNER="anyvm-org"
RB_REPO="${ANYVM_OSNAME}-builder"
BASE_URL="https://github.com/${RB_OWNER}/${RB_REPO}/releases/download/${ANYVM_RELEASE_TAG}"
debug_log "Selecting Builder ${BASE_URL:-'null'}"
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
  debug_log "fetching target from ${url}"
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

#export IMAGE_PATH
#printf '%s\n' "Image downloaded to $IMAGE_PATH"

# TODO: dynamically use --qcow2 when cached

# 3. start VM
# TODO: need way to use pid file eg --pidfile "$DATA_DIR/anyvm.pid"
START_ARGS=(--os "${ANYVM_OSNAME}" --mem "$ANYVM_MEM" --detach --builder "$ANYVM_VERSION")
if [ -n "$ANYVM_ARCH" ] ; then
  START_ARGS+=(--arch "${ANYVM_ARCH}")
fi
if [ -n "$ANYVM_RELEASE" ] ; then
  START_ARGS+=(--release "${ANYVM_RELEASE}")
fi
# with fixed CPU count
if [ -n "$ANYVM_CPU" ]; then
  START_ARGS+=(--cpu "$ANYVM_CPU")
fi
# with VNC disabled (CI focused)
if matches "$ANYVM_USE_VNC" "true" ; then
  printf "::warning file='%s',title='EXPOSED':: %s\n" "${0}" "VM's VNC is exposed. This is not recommended in a CI/CD environment!"
else
  START_ARGS+=(--vnc off)
fi

VM_SSH_HOST="127.0.0.1"
# get port robustly, default to 55555
VM_SSH_PORT=$(sh -c 'awk -v L=49154 -v H=64535 "BEGIN{srand(); print int(L+rand()*(H-L+1))}"')
VM_SSH_PORT="${VM_SSH_PORT:-55555}"

START_ARGS+=(--ssh-port "${VM_SSH_PORT}")

# TODO: make this more flexible via overrides and relative default
# HEURISTIC abort after 1/100th (1%) of step max timeout
# --boot-timeout-sec ( (($GITHUB_TIMEOUT * 60) / 100) )

debug_log "Starting ANYVM with args: ${START_ARGS[@]}" ;

python3 "$ANYVM_BIN" "${START_ARGS[@]}" ;

debug_log "=> Waiting for Guest VM to become available"

# wait_for_ssh: use nc if present, otherwise attempt ssh -o BatchMode test
wait_for_ssh(){ local h=$1 p=$2 t=${3:-180}; local s; s=$(date +%s); if command -v nc >/dev/null 2>&1; then
  while ! nc -z "$h" "$p"; do sleep 1; if [ $(( $(date +%s)-s )) -gt "$t" ]; then return 1; fi; done
else
  while ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$p" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$h" true 2>/dev/null; do
    sleep 1
    if [ $(( $(date +%s)-s )) -gt "$t" ]; then return 1; fi
  done
fi
}
wait_for_ssh "$VM_SSH_HOST" "$VM_SSH_PORT" 360 || die "SSH did not become available on $VM_SSH_HOST:$VM_SSH_PORT"

debug_log "Guest VM became available (on $VM_SSH_HOST:$VM_SSH_PORT)" ;

debug_log "Refreshing VM keys" ;
# 4. RSA-3072 ephemeral key generation with expiry comment
# TODO: don't use date (birthday-weakness)
EPHEM_KEY="${HOME:-.}/id_ci_vm_ephemeral_$(date -u +%s)_rsa"
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

# TODO: HEREMARK

# compute expiry timestamp (store in comment or file if needed)
# EXP_TS=$(( $(date +%s) + "$GITHUB_TIMEOUT" ))

# 4b. prepare env export script for the VM: gather non-sensitive GITHUB_* and INPUT_ENVS
ENV_SCRIPT_LOCAL="$DATA_DIR/env_forward.sh"
SAFE_GITHUB_LIST='GITHUB_ACTION GITHUB_ACTIONS GITHUB_WORKFLOW GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_JOB GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_REF GITHUB_SHA GITHUB_ACTOR'

debug_log "..=> Defining ssh env helper" ;

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

debug_log "..=> Defined" ;

# 4c. rotation: replace all users' authorized_keys (root) with ephemeral pubkey — safer atomic replace
EPHEM_PUB_CONTENT="$(cat ${EPHEM_KEY}.pub)"

debug_log "..=> Preparing script to rotate Guest VM keys" ;
ROTATE_ROOT_SCRIPT_PATH="$DATA_DIR/rotate_root_$$.sh"
cp -vf "${ANYVM_ROTATE_RKEYS_FILE}" "$ROTATE_ROOT_SCRIPT_PATH"
debug_log "..=> Staged" & debug_log "....=> Setting Permissions on staged script" ;
chmod +x "$ROTATE_ROOT_SCRIPT_PATH"

debug_log "....=> Ready to transfer \"${ROTATE_ROOT_SCRIPT_PATH}\" to Guest VM" ;

# 4d. copy rotation script and run it using baked key (best-effort)
if [ -f "$BAKED_PRIV" ]; then
  SSH_BAKED_OPTS=$(build_sendenv_opts);
  SSH_BAKED_OPTS="$SSH_BAKED_OPTS -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $BAKED_PRIV"
  debug_log "......=> Waiting for transfer" ;
  scp $SSH_BAKED_OPTS -P $VM_SSH_PORT "$ROTATE_ROOT_SCRIPT_PATH" root@"$VM_SSH_HOST":/tmp/rotate_root.sh || die "failed to scp rotate_root script"
  # TODO: cleanup local script copy once transferred
  debug_log "....=> Transferred" & {rm -f "$ROTATE_ROOT_SCRIPT_PATH" 2>/dev/null || true ;} & debug_log "..=> Waiting for rotation" &
  ssh $SSH_BAKED_OPTS -p $VM_SSH_PORT root@"$VM_SSH_HOST" "sh /tmp/rotate_root.sh '$(printf "%s" "$EPHEM_PUB_CONTENT" | sed "s/'/'\\\\''/g")'" || die "warning: rotate_root execution failed"
  debug_log "..=> Rotated"
else
  die "warning: baked private key not available; cannot run remote rotation via baked key"
fi

debug_log "=> Will now try ephemeral key pair"

SSH_EPHEMERAL_OPTS=$(build_sendenv_opts);
# verify ephemeral works (try a few times)
SSH_EPHEMERAL_OPTS="$SSH_EPHEMERAL_OPTS -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $EPHEM_KEY -o ConnectTimeout=5"
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
  ANYVM_BRIDGE_HOSTS_FILE="${ANYVM_BRIDGE_HOSTS_FILE}" SSH_EPHEMERAL_OPTS="$SSH_EPHEMERAL_OPTS" VM_SSH_HOST="$VM_SSH_HOST" VM_SSH_PORT="$VM_SSH_PORT" \
    "${ANYVM_UTIL_PATH_ARG}/bridge-hosts.sh"
else
  # best-effort fallback
  debug_log "Bridging via root"
  scp $SSH_EPHEMERAL_OPTS -P $VM_SSH_PORT /etc/hosts root@"$VM_SSH_HOST":/tmp/hosts.guest || die "failed to scp runner host file script"
  ssh $SSH_EPHEMERAL_OPTS -p $VM_SSH_PORT root@"$VM_SSH_HOST" "cat /tmp/hosts.guest >> /etc/hosts || true" || die "failed to clobber Guest /etc/hosts"
fi

debug_log "Bridging done"

# 4f. optionally create unprivileged user matching host and set its authorized_keys to its own ephemeral key
if [ "$VM_USER_CREATE" = "true" ]; then
  GUEST_USER="$HOST_USER"
  USER_EPHEM_DIR="$(mktemp -d)"
  USER_KEY="$USER_EPHEM_DIR/id_user_ci_rsa"
  ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$USER_KEY" -N "" -C "gha-user-ephemeral-$(date -u +%s)-ttl${GITHUB_TIMEOUT}s"
  USER_PUB="$(cat ${USER_KEY}.pub)"
  CREATE_USER_SCRIPT_PATH="$DATA_DIR/create_user_$$.sh"
  cat > "$CREATE_USER_SCRIPT_PATH" <<'CRUSER'
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
echo "done"
CRUSER

  chmod +x "$CREATE_USER_SCRIPT_PATH"

  # copy over script and run it via ephemeral root key (if ephemeral root works) otherwise baked
  if ssh $SSH_EPHEMERAL_OPTS -o BatchMode=yes root@"$VM_SSH_HOST" "true" >/dev/null 2>&1; then
    scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$EPHEM_KEY" "$CREATE_USER_SCRIPT_PATH" root@"$VM_SSH_HOST":/tmp/create_user.sh
    ssh $SSH_EPHEMERAL_OPTS root@"$VM_SSH_HOST" "bash /tmp/create_user.sh '$(printf "%s" "$GUEST_USER")' '$(printf "%s" "$USER_PUB" | sed "s/'/'\\\\''/g")'"
  elif [ -f "$BAKED_PRIV" ]; then
    scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$BAKED_PRIV" "$CREATE_USER_SCRIPT_PATH" root@"$VM_SSH_HOST":/tmp/create_user.sh
    ssh $SSH_BOOT_OPTS root@"$VM_SSH_HOST" "bash /tmp/create_user.sh '$(printf "%s" "$GUEST_USER")' '$(printf "%s" "$USER_PUB" | sed "s/'/'\\\\''/g")'"
  else
    echo "warning: neither ephemeral nor baked root access available; cannot create user"
  fi

  # set wrapper to use unpriv user key by default and use sudo for privileged ops
  WRAPPER="$DATA_DIR/ssh-to-vm.sh"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $USER_KEY "${GUEST_USER}@${VM_SSH_HOST}" "\$@"
EOF
  chmod +x "$WRAPPER"
else
  # wrapper uses root ephemeral key
  WRAPPER="$DATA_DIR/ssh-to-vm.sh"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $EPHEM_KEY "root@${VM_SSH_HOST}" "\$@"
EOF
  chmod +x "$WRAPPER"
fi

# 5. push env_forward and set it on guest (place in /etc/profile.d or user's shell rc)
# copy using ephemeral key if possible, else baked
if ssh $SSH_EPHEMERAL_OPTS -o BatchMode=yes root@"$VM_SSH_HOST" "true" >/dev/null 2>&1; then
  scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$EPHEM_KEY" "$ENV_SCRIPT_LOCAL" root@"$VM_SSH_HOST":/etc/profile.d/gha_env_forward.sh || true
elif [ -f "$BAKED_PRIV" ]; then
  scp $SSH_BOOT_OPTS "$ENV_SCRIPT_LOCAL" root@"$VM_SSH_HOST":/etc/profile.d/gha_env_forward.sh || true
fi

# 6. recreate full GITHUB_WORKSPACE path and rsync content
GITHUB_WS="${GITHUB_WORKSPACE:-$PWD}"
DEST_WS="$GITHUB_WS"
GUEST_RSYNC_USER="${GUEST_USER:-root}"
RSYNC_KEY="${USER_KEY:-$EPHEM_KEY}"

# ensure destination exists and owned by guest user if present
ssh ${SSH_BOOT_OPTS} root@${VM_SSH_HOST} "mkdir -p '$DEST_WS' && chown -R '${GUEST_RSYNC_USER}:${GUEST_RSYNC_USER}' '$DEST_WS'" || true

if [ "$SYNC_METHOD" = "rsync" ]; then
  rsync -a --delete -e "ssh -p $VM_SSH_PORT -i ${RSYNC_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "$GITHUB_WS/" "${GUEST_RSYNC_USER}@${VM_SSH_HOST}:$DEST_WS/"
else
  # Use trailing slash and /* glob to copy contents, not the directory itself
  scp -r -P "$VM_SSH_PORT" -i "${RSYNC_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$GITHUB_WS"/* "${GUEST_RSYNC_USER}@${VM_SSH_HOST}:$DEST_WS/"
fi

# 7. run startup hook if exists
ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && [ -x ./startup.sh ] && ./startup.sh || true" || true

# 8. run 'prepare' if provided
if [ -n "${INPUT_PREPARE:-}" ]; then
  ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && $INPUT_PREPARE"
fi

# 9. run CI command (required)
if [ -n "${INPUT_RUN:-}" ]; then
  ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && $INPUT_RUN"
fi

# 10. optional copyback
if [ "$COPYBACK" = "true" ]; then
  rsync -a -e "ssh -p $VM_SSH_PORT -i ${RSYNC_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" ${GUEST_RSYNC_USER}@${VM_SSH_HOST}:"${DEST_WS}/" "$GITHUB_WS/ci-copyback/" || true
fi

# 10b afterwards
if [ -n "${INPUT_AFTERWARDS:-}" ]; then
  ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && $INPUT_AFTERWARDS"
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
rm -rf "$EPHEM_DIR" "$ROTATE_ROOT_SCRIPT_PATH" || true
[ -n "${USER_EPHEM_DIR:-}" ] && rm -rf "$USER_EPHEM_DIR" || true
[ -n "${CREATE_USER_SCRIPT_PATH:-}" ] && rm -f "$CREATE_USER_SCRIPT_PATH" || true
echo "done"
