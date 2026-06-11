#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Inputs
OSNAME="${INPUT_OSNAME:-FreeBSD}"
RELEASE="${INPUT_RELEASE:-}"
ARCH="${INPUT_ARCH:-}"
MEM="${INPUT_MEM:-6144}"
CPU="${INPUT_CPU:-}"
ANYVM_TAG="${INPUT_ANYVM_TAG:-v0.0.0}"    # pin this
CACHE_DIR="${INPUT_CACHE_DIR:-${RUNNER_TEMP:-/tmp}/anyvm-cache}"
DATA_DIR="${INPUT_DATA_DIR:-$CACHE_DIR/data}"
VM_USER_CREATE="${INPUT_CREATE_USER:-true}"    # create non-root user by default
HOST_USER="${INPUT_HOST_USER:-${RUNNER_USER:-$(whoami)}}"
GITHUB_TIMEOUT="${INPUT_TIMEOUT:-${JOB_TIMEOUT:-3600}}"  # seconds; JOB_TIMEOUT can be set by workflow
VNC_DISABLE="${INPUT_VNC_DISABLE:-true}"
SYNC_METHOD="${INPUT_SYNC:-rsync}"
COPYBACK="${INPUT_COPYBACK:-true}"
ENV_INPUTS="${INPUT_ENVS:-}"
EPHEM_KEY_TYPE="rsa"
EPHEM_KEY_BITS=3072

mkdir -p "$CACHE_DIR" "$DATA_DIR"

# 1. Install QEMU (minimal cross-platform approach)
install_qemu(){
  if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "qemu present"
    return
  fi
  case "$(uname -s)" in
    Linux)
      sudo apt-get update && sudo apt-get install -y qemu-system-x86 qemu-utils || \
      sudo yum install -y qemu-kvm qemu-img || true
      ;;
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew required on macOS to install qemu"; exit 1
      fi
      brew install qemu
      ;;
    MINGW*|MSYS*|CYGWIN*)
      choco install qemu -y || true
      ;;
    *)
      echo "Unsupported runner OS"; exit 1
      ;;
  esac
}
install_qemu

# 2. fetch anyvm from github and use its anyvm.py
ANYVM_REPO_DIR="$CACHE_DIR/anyvm-src"
if [ ! -d "$ANYVM_REPO_DIR" ]; then
  git clone --depth 1 --branch "$ANYVM_TAG" https://github.com/anyvm-org/anyvm.git "$ANYVM_REPO_DIR"
else
  (cd "$ANYVM_REPO_DIR" && git fetch --depth 1 origin "$ANYVM_TAG" && git checkout "$ANYVM_TAG")
fi
ANYVM_BIN="$ANYVM_REPO_DIR/anyvm.py"
chmod +x "$ANYVM_BIN"

# 3. prepare runner cache (caller workflow should also use actions/cache)
# create cache dirs
mkdir -p "$CACHE_DIR/bin" "$DATA_DIR/images"

# 4. fetch image + baked ssh keys (assume anyvm provides image and baked pubkey)
python3 "$ANYVM_BIN" fetch --os "$OSNAME" --release "$RELEASE" --arch "$ARCH" --out "$DATA_DIR/images" --cache-dir "$CACHE_DIR"
IMAGE_PATH=$(ls -1 "$DATA_DIR/images"/* | head -n1)
BAKED_PUB="$DATA_DIR/baked_id_rsa.pub"
BAKED_PRIV="$DATA_DIR/baked_id_rsa"
# if anyvm stores keys elsewhere adjust accordingly

# 5. start VM with VNC disabled
START_ARGS=(--image "$IMAGE_PATH" --mem "$MEM" --cpu "$CPU" --background --pidfile "$DATA_DIR/anyvm.pid")
if [ "$VNC_DISABLE" = "true" ]; then
  START_ARGS+=(--no-vnc)
fi
python3 "$ANYVM_BIN" start "${START_ARGS[@]}"

VM_SSH_HOST="127.0.0.1"
VM_SSH_PORT="$(python3 "$ANYVM_BIN" ssh-port --pidfile "$DATA_DIR/anyvm.pid" || echo 2222)"
wait_for_ssh(){ local h=$1 p=$2 t=${3:-180}; local s; s=$(date +%s); while ! nc -z "$h" "$p"; do sleep 1; if [ $(( $(date +%s)-s )) -gt "$t" ]; then return 1; fi; done; }
wait_for_ssh "$VM_SSH_HOST" "$VM_SSH_PORT" 180

# 6. RSA-3072 ephemeral key generation with expiry comment
EPHEM_DIR="$(mktemp -d)"
EPHEM_KEY="$EPHEM_DIR/id_ci_vm_rsa"
ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$EPHEM_KEY" -N "" -C "gha-ephemeral-$(date -u +%s)-ttl${GITHUB_TIMEOUT}s"

# compute expiry timestamp (store in comment or file if needed)
EXP_TS=$(( $(date +%s) + GITHUB_TIMEOUT ))

# 6b. copy host /etc/hosts to guest (temp file)
scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$BAKED_PRIV" /etc/hosts root@"$VM_SSH_HOST":/tmp/hosts.guest || true
ssh -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$BAKED_PRIV" root@"$VM_SSH_HOST" "cat /tmp/hosts.guest > /etc/hosts || true"

# 6c. prepare env export script for the VM: gather non-sensitive GITHUB_* and INPUT_ENVS
ENV_SCRIPT="/tmp/gha_env_export.sh"
{
  echo "#!/bin/sh"
  # forward non-sensitive GITHUB_* variables (filter)
  for var in $(env | grep '^GITHUB_' | cut -d= -f1); do
    case "$var" in
      GITHUB_ACTION|GITHUB_ACTIONS|GITHUB_WORKFLOW|GITHUB_RUN_ID|GITHUB_RUN_NUMBER|GITHUB_JOB|GITHUB_REPOSITORY|GITHUB_REPOSITORY_OWNER|GITHUB_REF|GITHUB_SHA|GITHUB_ACTOR)
        echo "export $var='${!var}'"
        ;;
      *)
        # skip potentially sensitive ones
        ;;
    esac
  done
  # inject user-specified envs in INPUT_ENVS (format KEY=VAL; comma or newline separated)
  if [ -n "$ENV_INPUTS" ]; then
    IFS=$'\n,'; for e in $ENV_INPUTS; do
      k=$(echo "$e" | cut -d= -f1); v=$(echo "$e" | cut -d= -f2-)
      echo "export $k='${v}'"
    done
    unset IFS
  fi
} > "$DATA_DIR/env_forward.sh"
chmod +x "$DATA_DIR/env_forward.sh"

# 6d. rotation: replace all users' authorized_keys (root) with ephemeral pubkey and optionally create non-root user
EPH_PUB_CONTENT="$(cat ${EPHEM_KEY}.pub)"
SSH_BOOT_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $BAKED_PRIV"

# rotation script executed as root on guest
ROTATE_ROOT_SCRIPT=$(cat <<'EOF'
set -euo pipefail
NEW_PUB="$1"
# remove all authorized_keys for all users (best-effort): scan /home and root
for homedir in /root /home/*; do
  [ -d "$homedir" ] || continue
  mkdir -p "$homedir/.ssh"
  echo "$NEW_PUB" > "$homedir/.ssh/authorized_keys"
  chmod 600 "$homedir/.ssh/authorized_keys"
  chown $(basename "$homedir"):"$(basename "$homedir")" "$homedir/.ssh/authorized_keys" 2>/dev/null || true
done
# also set root's authorized_keys
echo "$NEW_PUB" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
# reload sshd safely on FreeBSD / Linux variants
if command -v service >/dev/null 2>&1; then
  service sshd reload || service sshd restart || true
else
  systemctl try-reload-or-restart sshd || systemctl restart sshd || true
fi
# remove other sessions (best-effort)
pkill -KILL -u root || true
EOF
)

ssh $SSH_BOOT_OPTS root@"$VM_SSH_HOST" "bash -s" <<EOF
$(echo "$ROTATE_ROOT_SCRIPT")
EOF <<EOD
$EPH_PUB_CONTENT
EOD

# verify ephemeral works
SSH_EPHEMERAL_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT -i $EPHEM_KEY"
ssh $SSH_EPHEMERAL_OPTS -o BatchMode=yes root@"$VM_SSH_HOST" "echo OK" >/dev/null 2>&1

# 6e. optionally create unprivileged user matching host and set its authorized_keys to its own ephemeral key
if [ "$VM_USER_CREATE" = "true" ]; then
  GUEST_USER="$HOST_USER"
  # generate separate ephemeral key for user
  USER_EPHEM_DIR="$(mktemp -d)"
  USER_KEY="$USER_EPHEM_DIR/id_user_ci_rsa"
  ssh-keygen -t "$EPHEM_KEY_TYPE" -b "$EPHEM_KEY_BITS" -f "$USER_KEY" -N "" -C "gha-user-ephemeral-$(date -u +%s)-ttl${GITHUB_TIMEOUT}s"
  USER_PUB="$(cat ${USER_KEY}.pub)"
  # create user and set key
  CREATE_USER_SCRIPT=$(cat <<'EOS'
set -euo pipefail
USERNAME="$1"
USER_PUB="$2"
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/sh "$USERNAME" || adduser -D -s /bin/sh "$USERNAME" || true
fi
mkdir -p /home/"$USERNAME"/.ssh
echo "$USER_PUB" > /home/"$USERNAME"/.ssh/authorized_keys
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh
# allow wheel sudo without password if desired (optional)
if command -v pw >/dev/null 2>&1; then
  # FreeBSD path: add to wheel
  pw usermod "$USERNAME" -G wheel || true
fi
echo "done"
EOS
)
  ssh $SSH_EPHEMERAL_OPTS root@"$VM_SSH_HOST" "bash -s" <<EOF
$(echo "$CREATE_USER_SCRIPT")
EOF <<EOD
$GUEST_USER
$USER_PUB
EOD

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
scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$EPHEM_KEY" "$DATA_DIR/env_forward.sh" root@"$VM_SSH_HOST":/etc/profile.d/gha_env_forward.sh || true

# 8. recreate full GITHUB_WORKSPACE path and rsync content
GITHUB_WS="${GITHUB_WORKSPACE:-$PWD}"
DEST_WS="$GITHUB_WS"  # recreate same path on guest
ssh $SSH_EPHEMERAL_OPTS root@"$VM_SSH_HOST" "mkdir -p '$DEST_WS' && chown -R ${GUEST_USER:-root}: ${DEST_WS} || true"
if [ "$SYNC_METHOD" = "rsync" ]; then
  rsync -a --delete -e "ssh -p $VM_SSH_PORT -i ${USER_KEY:-$EPHEM_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "$GITHUB_WS/" "root@$VM_SSH_HOST:$DEST_WS/"
else
  scp -r -P "$VM_SSH_PORT" -i "${USER_KEY:-$EPHEM_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$GITHUB_WS" root@"$VM_SSH_HOST":"$DEST_WS"
fi

# 9. run startup hook if exists
ssh ${USER_KEY:+-i $USER_KEY} -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_USER:-root}@"$VM_SSH_HOST" "cd '$DEST_WS' && [ -x ./startup.sh ] && ./startup.sh || true"

# 10. run 'prepare' if provided
if [ -n "${INPUT_PREPARE:-}" ]; then
  ssh ${USER_KEY:+-i $USER_KEY} -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_USER:-root}@"$VM_SSH_HOST" "cd '$DEST_WS' && $INPUT_PREPARE"
fi

# 11. run CI command (required)
if [ -n "${INPUT_RUN:-}" ]; then
  ssh ${USER_KEY:+-i $USER_KEY} -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_USER:-root}@"$VM_SSH_HOST" "cd '$DEST_WS' && $INPUT_RUN"
fi

# 12. optional copyback
if [ "$COPYBACK" = "true" ]; then
  rsync -a -e "ssh -p $VM_SSH_PORT -i ${USER_KEY:-$EPHEM_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" ${GUEST_USER:-root}@"$VM_SSH_HOST":"$DEST_WS"/ "$GITHUB_WS/ci-copyback/" || true
fi

# 12b afterwards
if [ -n "${INPUT_AFTERWARDS:-}" ]; then
  ssh ${USER_KEY:+-i $USER_KEY} -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${GUEST_USER:-root}@"$VM_SSH_HOST" "cd '$DEST_WS' && $INPUT_AFTERWARDS"
fi

# 13. stop VM and cleanup
python3 "$ANYVM_BIN" stop --pidfile "$DATA_DIR/anyvm.pid" || true
if [ -f "$DATA_DIR/anyvm.pid" ]; then
  kill "$(cat "$DATA_DIR/anyvm.pid")" 2>/dev/null || true; rm -f "$DATA_DIR/anyvm.pid"
fi
# shred keys
shred -u "${EPHEM_KEY}" || rm -f "${EPHEM_KEY}"
[ -n "${USER_KEY:-}" ] && (shred -u "${USER_KEY}" || rm -f "${USER_KEY}")
rm -rf "$EPHEM_DIR" "${USER_EPHEM_DIR:-/dev/null}"
echo "done"
