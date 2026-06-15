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
input_path="$0"
# Remove the trailing slash if present
input_path="${input_path%/}"
# Extract the directory name
ANYVM_UTIL_PATH_ARG="${input_path%/*}"

if [ -d "$ANYVM_UTIL_PATH_ARG" ] && [ ":$PATH:" != *":$ANYVM_UTIL_PATH_ARG:"* ] ; then
	PATH="${PATH:+"$PATH:"}$ANYVM_UTIL_PATH_ARG" ;
	export PATH ;
fi

unset input_path ;
set -euo
IFS=$'\n\t'

# Inputs
ANYVM_OSNAME="${INPUT_OSNAME:-freebsd}"  # freebsd / ghostbsd / openbsd / netbsd / dragonflybsd / midnightbsd / solaris / omnios / openindiana / tribblix / haiku / ubuntu / blissos
ANYVM_RELEASE="${INPUT_RELEASE:-}"
ANYVM_ARCH="${INPUT_ARCH:-}"  # x86_64 / aarch64 / riscv64 / s390x / powerpc64 / ppc64le / sparc64
ANYVM_MEM="${INPUT_MEM:-6144}"
ANYVM_CPU="${INPUT_CPU:-}"
ANYVM_CPU_ARCH="${INPUT_CPU_ARCH:-}"  # optional VM specific CPU model
ANYVM_VERSION="${ANYVM_VERSION:-2.1.7}"    # pin this per OS builder
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
EPHEM_KEY_TYPE="rsa"
EPHEM_KEY_BITS=3072

mkdir -p "$ANYVM_CACHE_DIR" "$DATA_DIR"

# helper: fail with message
debug_log(){ if $DEBUG; then printf '::debug:: %s\n' "$*" >&2; fi; }

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
        sudo apt-get update && sudo apt-get install --no-install-recommends -y \
          zstd ovmf xz-utils qemu-utils ca-certificates \
          qemu-system-x86 qemu-system-arm qemu-efi-aarch64 \
          qemu-efi-riscv64 qemu-system-riscv64 qemu-system-misc u-boot-qemu \
          qemu-system-ppc qemu-system-s390x qemu-system-sparc \
          openssh-client || true
      elif command -v yum >/dev/null 2>&1; then
        printf '%s\n' "Unsupported runner OS"
        sudo yum install -y qemu-kvm qemu-img || true
      fi
      ;;
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install qemu ;
      else
        die "Homebrew required on macOS to install qemu"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if command -v choco >/dev/null 2>&1; then
        choco install qemu -y || true
      fi
      ;;
    *)
      die "Unsupported runner OS"
      ;;
  esac
}
install_qemu

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

mkdir -p "$ANYVM_CACHE_DIR" "$DATA_DIR/images"

# Download anyvm.py (kept)
ANYVM_PY_PATH="$ANYVM_CACHE_DIR/anyvm.py"
ANYVM_URL="https://raw.githubusercontent.com/anyvm-org/anyvm/${ANYVM_SHA}/anyvm.py"
download_file "$ANYVM_URL" "$ANYVM_PY_PATH" || die "failed to download anyvm.py"
chmod +x "$ANYVM_PY_PATH" || true
ANYVM_BIN="$ANYVM_PY_PATH"

ANYVM_NAME_SUFFIX=""
ANYVM_RELEASE_TAG="v${ANYVM_VERSION}"
RB_OWNER="anyvm-org"
RB_REPO="${ANYVM_OSNAME}-builder"
BASE_URL="https://github.com/${RB_OWNER}/${RB_REPO}/releases/download/${ANYVM_RELEASE_TAG}"
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

# 3. Try image extensions (preferred order)
IMAGE_PATH=""
for ext in "qcow2.zst" "qemu"; do
  cand="$DATA_DIR/images/${ANYVM_NAME}.${ext}"
  url="${BASE_URL}/${ANYVM_NAME}.${ext}"
  if download_file "$url" "$cand"; then
    IMAGE_PATH="$cand"; chmod 644 "$IMAGE_PATH" || true;
  fi
done
[ -n "$IMAGE_PATH" ] || die "no image found for ${ANYVM_NAME} (.qcow2.zst nor .qemu) in ${DATA_DIR}/images"

# 4. Keys: .pub (public) and .id_rsa (private)
BAKED_PUB="$DATA_DIR/${ANYVM_NAME}.pub"
BAKED_PRIV="$DATA_DIR/${ANYVM_NAME}"

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

# 5. start VM with VNC disabled
START_ARGS=(--image "$IMAGE_PATH" --mem "$ANYVM_MEM" --detach --builder "$ANYVM_VERSION" --pidfile "$DATA_DIR/anyvm.pid")
if [ -n "$ANYVM_RELEASE" ] ; then
  START_ARGS+=(--release "${ANYVM_RELEASE}")
fi
if [ -n "$ANYVM_CPU" ]; then
  START_ARGS+=(--cpu "$ANYVM_CPU")
fi
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


python3 "$ANYVM_BIN" "${START_ARGS[@]}"

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

# 6. RSA-3072 ephemeral key generation with expiry comment
EPHEM_DIR="$(mktemp -d)"
EPHEM_KEY="$EPHEM_DIR/id_ci_vm_rsa"
ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$EPHEM_KEY" -N "" -C "gha-ephemeral-$(date -u +%s)"

# compute expiry timestamp (store in comment or file if needed)
# EXP_TS=$(( $(date +%s) + "$GITHUB_TIMEOUT" ))

# 6b. prepare env export script for the VM: gather non-sensitive GITHUB_* and INPUT_ENVS
ENV_SCRIPT_LOCAL="$DATA_DIR/env_forward.sh"
{
  echo "#!/bin/sh"
  # forward a selective whitelist of GITHUB_* variables (escape single quotes)
  for var in $(env | awk -F= '/^GITHUB_/ {print $1}'); do
    case "$var" in
      GITHUB_ACTION|GITHUB_ACTIONS|GITHUB_WORKFLOW|GITHUB_RUN_ID|GITHUB_RUN_NUMBER|GITHUB_JOB|GITHUB_REPOSITORY|GITHUB_REPOSITORY_OWNER|GITHUB_REF|GITHUB_SHA|GITHUB_ACTOR)
        val="${!var}"
        # escape single quotes safely
        val_esc=$(printf "%s" "$val" | sed "s/'/'\\\\''/g")
        echo "export $var='$val_esc'"
        ;;
      *)
        ;;
    esac
  done
  # inject user-specified envs in INPUT_ENVS (format KEY=VAL; comma or newline separated)
  if [ -n "$ENV_INPUTS" ]; then
    IFS=$'\n,'; for e in $ENV_INPUTS; do
      k=$(printf "%s" "$e" | cut -d= -f1); v=$(printf "%s" "$e" | cut -d= -f2-)
      k=$(printf "%s" "$k" | sed 's/[^A-Za-z0-9_]/_/g')
      v_esc=$(printf "%s" "$v" | sed "s/'/'\\\\''/g")
      echo "export $k='$v_esc'"
    done
    unset IFS
  fi
} > "$ENV_SCRIPT_LOCAL"
chmod +x "$ENV_SCRIPT_LOCAL"

# 6c. rotation: replace all users' authorized_keys (root) with ephemeral pubkey — safer atomic replace
EPHEM_PUB_CONTENT="$(cat ${EPHEM_KEY}.pub)"
ROTATE_ROOT_SCRIPT_PATH="$DATA_DIR/rotate_root_$$.sh"
cat > "$ROTATE_ROOT_SCRIPT_PATH" <<'ROTSCR'
#!/usr/bin/env bash
set -euo
NEW_PUB="$1"
# write to temp and atomically move for each homedir
for homedir in /root /home/*; do
  [ -d "$homedir" ] || continue
  mkdir -p "$homedir/.ssh"
  tmp=$(mktemp -p "$homedir/.ssh" auth.XXXXXX)
  printf '%s\n' "$NEW_PUB" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$homedir/.ssh/authorized_keys"
  # try to set ownership if home directory name matches username
  user=$(basename "$homedir")
  chown "$user":"$user" "$homedir/.ssh/authorized_keys" 2>/dev/null || true
done
# ensure root authorized_keys
mkdir -p /root/.ssh
tmp_root=$(mktemp -p /root/.ssh auth.XXXXXX)
printf '%s\n' "$NEW_PUB" > "$tmp_root"
chmod 600 "$tmp_root"
mv "$tmp_root" /root/.ssh/authorized_keys || true
# reload sshd safely (try multiple names)
if command -v service >/dev/null 2>&1; then
  service sshd reload || service sshd restart || service ssh restart || true
else
  if command -v systemctl >/dev/null 2>&1; then
    systemctl try-reload-or-restart sshd.service || systemctl restart sshd.service || systemctl restart ssh.service || true
  fi
fi
ROTSCR
chmod +x "$ROTATE_ROOT_SCRIPT_PATH"

# 6d. copy rotation script and run it using baked key (best-effort)
if [ -f "$BAKED_PRIV" ]; then
  scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$BAKED_PRIV" "$ROTATE_ROOT_SCRIPT_PATH" root@"$VM_SSH_HOST":/tmp/rotate_root.sh || die "failed to scp rotate_root script"
  ssh $SSH_BOOT_OPTS root@"$VM_SSH_HOST" "bash /tmp/rotate_root.sh '$(printf "%s" "$EPHEM_PUB_CONTENT" | sed "s/'/'\\\\''/g")'" || echo "warning: rotate_root execution failed"
else
  die "warning: baked private key not available; cannot run remote rotation via baked key"
fi

# verify ephemeral works (try a few times)
SSH_EPHEMERAL_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $EPHEM_KEY -o ConnectTimeout=5"
ok=1
for _step in 1 2 3; do
  if ssh $SSH_EPHEMERAL_OPTS -o BatchMode=yes root@"$VM_SSH_HOST" "echo OK" >/dev/null 2>&1; then ok=0; break; fi
  sleep 1
done
if [ $ok -ne 0 ]; then
  die "warning: ephemeral key login failed; continuing with subsequent steps will fail"
fi

# 6e. copy host /etc/hosts to guest (temp file) - best-effort
SSH_BOOT_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $EPHEM_KEY"
if [ -x ${ANYVM_UTIL_PATH_ARG}/at_bootstrap_merge_hosts_to_vm.sh ]; then
  "${ANYVM_UTIL_PATH_ARG}/at_bootstrap_merge_hosts_to_vm.sh" ;
else
  # best-effort fallback
  scp $SSH_BOOT_OPTS /etc/hosts root@"$VM_SSH_HOST":/tmp/hosts.guest || true
  ssh $SSH_BOOT_OPTS root@"$VM_SSH_HOST" "cat /tmp/hosts.guest >> /etc/hosts || true" || true
fi

# 6f. optionally create unprivileged user matching host and set its authorized_keys to its own ephemeral key
if [ "$VM_USER_CREATE" = "true" ]; then
  GUEST_USER="$HOST_USER"
  USER_EPHEM_DIR="$(mktemp -d)"
  USER_KEY="$USER_EPHEM_DIR/id_user_ci_rsa"
  ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$USER_KEY" -N "" -C "gha-user-ephemeral-$(date -u +%s)-ttl${GITHUB_TIMEOUT}s"
  USER_PUB="$(cat ${USER_KEY}.pub)"
  CREATE_USER_SCRIPT_PATH="$DATA_DIR/create_user_$$.sh"
  cat > "$CREATE_USER_SCRIPT_PATH" <<'CRUSER'
#!/usr/bin/env bash
set -euo
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
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $USER_KEY "\$@"
EOF
  chmod +x "$WRAPPER"
else
  # wrapper uses root ephemeral key
  WRAPPER="$DATA_DIR/ssh-to-vm.sh"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $EPHEM_KEY "\$@"
EOF
  chmod +x "$WRAPPER"
fi

# 7. push env_forward and set it on guest (place in /etc/profile.d or user's shell rc)
# copy using ephemeral key if possible, else baked
if ssh $SSH_EPHEMERAL_OPTS -o BatchMode=yes root@"$VM_SSH_HOST" "true" >/dev/null 2>&1; then
  scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$EPHEM_KEY" "$ENV_SCRIPT_LOCAL" root@"$VM_SSH_HOST":/etc/profile.d/gha_env_forward.sh || true
elif [ -f "$BAKED_PRIV" ]; then
  scp $SSH_BOOT_OPTS "$ENV_SCRIPT_LOCAL" root@"$VM_SSH_HOST":/etc/profile.d/gha_env_forward.sh || true
fi

# 8. recreate full GITHUB_WORKSPACE path and rsync content
GITHUB_WS="${GITHUB_WORKSPACE:-$PWD}"
DEST_WS="$GITHUB_WS"
GUEST_RSYNC_USER="${GUEST_USER:-root}"
RSYNC_KEY="${USER_KEY:-$EPHEM_KEY}"

# ensure destination exists and owned by guest user if present
ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "mkdir -p '$DEST_WS' && chown -R ${GUEST_RSYNC_USER}:${GUEST_RSYNC_USER} '$DEST_WS' || true" || true

if [ "$SYNC_METHOD" = "rsync" ]; then
  rsync -a --delete -e "ssh -p $VM_SSH_PORT -i ${RSYNC_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "$GITHUB_WS/" "${GUEST_RSYNC_USER}@${VM_SSH_HOST}:$DEST_WS/"
else
  # Use trailing slash and /* glob to copy contents, not the directory itself
  scp -r -P "$VM_SSH_PORT" -i "${RSYNC_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$GITHUB_WS"/* "${GUEST_RSYNC_USER}@${VM_SSH_HOST}:$DEST_WS/"
fi

# 9. run startup hook if exists
ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && [ -x ./startup.sh ] && ./startup.sh || true" || true

# 10. run 'prepare' if provided
if [ -n "${INPUT_PREPARE:-}" ]; then
  ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && $INPUT_PREPARE"
fi

# 11. run CI command (required)
if [ -n "${INPUT_RUN:-}" ]; then
  ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && $INPUT_RUN"
fi

# 12. optional copyback
if [ "$COPYBACK" = "true" ]; then
  rsync -a -e "ssh -p $VM_SSH_PORT -i ${RSYNC_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" ${GUEST_RSYNC_USER}@${VM_SSH_HOST}:"${DEST_WS}/" "$GITHUB_WS/ci-copyback/" || true
fi

# 12b afterwards
if [ -n "${INPUT_AFTERWARDS:-}" ]; then
  ssh -i "$RSYNC_KEY" -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_RSYNC_USER}@${VM_SSH_HOST} "cd '$DEST_WS' && $INPUT_AFTERWARDS"
fi

# 13. stop VM and cleanup
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
