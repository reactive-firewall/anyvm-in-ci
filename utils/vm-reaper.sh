#!/bin/sh
# vm-reaper.sh  -- Hardened, minimal-output stopper for detached/hung qemu VMs
# Usage examples:
#  sudo DRY_RUN=1 ./vm-reaper.sh --pid 1234
#  sudo ./vm-reaper.sh --name qemu-system-x86_64
#  sudo ./vm-reaper.sh --monitor /tmp/qemu-monitor.sock

TIMOUT_TERM=5
TIMEOUT_KILL=3

# Configuration: set DRY_RUN=1 to show planned actions only (safe for logs)
DRY_RUN=${DRY_RUN:-0}

QEMU_PROC_RE='(^|[[:space:]/])(qemu-system-[^[:space:]/]+|qemu-kvm)([[:space:]]|$)'

# Helper: print short, non-sensitive message to stderr
log() { printf '[vm-reaper] %s\n' "$1" >&2; }

# Helper: display an obfuscated version of a token (keep last 4 chars)
obf() {
  t="$1"
  [ -z "$t" ] && { printf '<empty>'; return; }
  len=$(printf '%s' "$t" | wc -c | tr -d ' ')
  if [ "$len" -le 8 ]; then
    printf '***%s' "$(printf '%s' "$t" | sed -e 's/./*/g')"
  else
    tail="$(printf '%s' "$t" | tail -c 5)"
    printf '***%s' "$tail"
  fi
}

# Helper: validate that a PID is a positive integer
is_positive_pid() {
  _pid="$1"
  # Check if empty
  [ -z "$_pid" ] && return 1
  # Check if it matches the pattern: one or more digits, no other characters
  case "$_pid" in
    *[!0-9]*) return 1 ;;
    '') return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

# Helper: validate that a process at PID is a QEMU process
is_qemu_pid() {
  _pid="$1"
  [ -z "$_pid" ] || [ "$_pid" -eq 0 ] 2>/dev/null && return 1
  # Use ps to get the command line and check if it matches QEMU pattern
  _ps_output="$(ps -p "$_pid" -o args= 2>/dev/null || true)"
  [ -z "$_ps_output" ] && return 1
  # Check if output matches qemu pattern (already defined in script)
  printf '%s' "$_ps_output" | grep -Eq "$QEMU_PROC_RE"
}

# Minimal arg parsing
PID=""
PROC_NAME=""
MONITOR=""
require_value() {
  [ -n "${2:-}" ] || { log "Missing value for $1"; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pid) require_value "$1" "${2:-}"; PID="$2"; shift 2;;
    --name) require_value "$1" "${2:-}"; PROC_NAME="$2"; shift 2;;
    --monitor) require_value "$1" "${2:-}"; MONITOR="$2"; shift 2;;
    --help) printf "Usage: %s [--pid PID] [--name PROC_NAME] [--monitor /path]\n" "$0"; exit 0;;
    *) log "Unknown arg"; exit 2;;
  esac
done

# Resolve a PID if name provided (avoid printing command lines)
if [ -z "$PID" ] && [ -n "$PROC_NAME" ]; then
  if command -v pgrep >/dev/null 2>&1; then
    PID="$(pgrep -f "$PROC_NAME" | head -n1 || true)"
  else
    PID="$(ps -ef 2>/dev/null | awk -v pat="$PROC_NAME" '$0 ~ pat {print $2; exit}' || true)"
  fi
fi

# If still none, try common qemu names but do not reveal matches
if [ -z "$PID" ]; then
  if command -v pgrep >/dev/null 2>&1; then
    PID="$(pgrep -f "$QEMU_PROC_RE" | head -n1 || true)"
  else
    PID="$(ps -ef 2>/dev/null | awk -v pat="$QEMU_PROC_RE" '$0 ~ pat {print $2; exit}' || true)"
  fi
fi

is_running() {
  [ -n "$1" ] || return 1
  kill -0 "$1" 2>/dev/null
}

# Do not disclose MONITOR path; show obfuscated token instead
if [ -n "$MONITOR" ]; then
  obf_mon="$(obf "$MONITOR")"
  log "Monitor provided: $obf_mon"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY_RUN: would send system_powerdown to monitor ($obf_mon)"
  else
    if command -v socat >/dev/null 2>&1; then
      printf "system_powerdown\n" | socat - UNIX-CONNECT:"$MONITOR" >/dev/null 2>&1 || true
      log "Requested graceful shutdown via monitor ($obf_mon)"
    elif command -v ncat >/dev/null 2>&1; then
      printf "system_powerdown\n" | ncat -U "$MONITOR" >/dev/null 2>&1 || true
      log "Requested graceful shutdown via monitor ($obf_mon)"
    else
      log "No socket tool (socat/ncat); skipping monitor attempt"
    fi
    sleep 1
  fi
fi

# If PID known, attempt TERM then KILL, but only log obfuscated PID
if [ -n "$PID" ]; then
  # Validate PID before signaling
  if ! is_positive_pid "$PID"; then
    log "Error: invalid PID format $(obf "$PID")"
    exit 1
  fi
  
  # Validate that PID is a QEMU process before signaling
  if ! is_qemu_pid "$PID"; then
    log "Error: process $(obf "$PID") is not a QEMU process"
    exit 1
  fi
  
  pid_obf="pid=$(obf "$PID")"
  if is_running "$PID"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY_RUN: would send SIGTERM to $pid_obf"
    else
      log "Sending SIGTERM to $pid_obf"
      kill "$PID" 2>/dev/null || true
      i=0
      while is_running "$PID" && [ "$i" -lt "$TIMOUT_TERM" ]; do sleep 1; i=$((i+1)); done
      if is_running "$PID"; then
        log "SIGTERM failed; sending SIGKILL to $pid_obf"
        kill -9 "$PID" 2>/dev/null || true
        j=0
        while is_running "$PID" && [ "$j" -lt "$TIMEOUT_KILL" ]; do sleep 1; j=$((j+1)); done
      fi
    fi
  else
    log "No running process for $pid_obf"
  fi
else
  # No PID: do a conservative name-based termination without printing matched command-lines
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY_RUN: would attempt to pkill qemu processes by safe name match"
  else
    if command -v pkill >/dev/null 2>&1; then
      pkill -f 'qemu(-system|-kvm)?' 2>/dev/null || true
      sleep "$TIMOUT_TERM"
      pkill -9 -f 'qemu(-system|-kvm)?' 2>/dev/null || true
      log "Requested termination of qemu processes by safe name match"
    else
      # fallback: iterate pids but only log counts
      PS_PIDS="$(ps -ef 2>/dev/null | awk '/qemu(-system|-kvm)?/ && !/awk/ {print $2}')"
      cnt=0
      for p in $PS_PIDS; do
        cnt=$((cnt+1))
        kill "$p" 2>/dev/null || true
      done
      log "Attempted kill on ${cnt:=0} matching process(es)"
      sleep "$TIMOUT_TERM"
      # escalate
      for p in $PS_PIDS; do
        kill -9 "$p" 2>/dev/null || true
      done
    fi
  fi
fi

# Final verification: only return a concise numeric status (no cmdlines)
remaining=0
if command -v pgrep >/dev/null 2>&1; then
  remaining="$(pgrep -f 'qemu(-system|-kvm)?' | wc -l 2>/dev/null || true)"
else
  remaining="$(ps -ef 2>/dev/null | awk '/qemu(-system|-kvm)?/ && !/awk/ {c++} END{print c+0}')"
fi
log "Remaining qemu processes: $remaining"

# Exit code: 0 if no remaining qemu processes, 1 otherwise
if [ "$remaining" -eq 0 ]; then
  log "All done" ;
  exit 0
else
  exit 1
fi
