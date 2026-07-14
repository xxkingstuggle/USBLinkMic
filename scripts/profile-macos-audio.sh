#!/bin/zsh
set -euo pipefail

PROCESS_NAME="${1:-USB LinkMic}"
DURATION="${2:-10}"
OUTPUT_DIR="${3:-${TMPDIR%/}/usblinkmic-profile-$(date +%Y%m%d-%H%M%S)}"

if ! [[ "$DURATION" =~ '^[0-9]+$' ]] || (( DURATION < 3 )); then
  echo "duration must be an integer of at least 3 seconds" >&2
  exit 2
fi

PID="$(pgrep -x "$PROCESS_NAME" | head -1 || true)"
if [[ -z "$PID" ]]; then
  echo "process not found: $PROCESS_NAME" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

{
  echo "timestamp=$(date -Iseconds)"
  echo "process=$PROCESS_NAME"
  echo "pid=$PID"
  ps -p "$PID" -o pid=,ppid=,%cpu=,%mem=,rss=,vsz=,etime=,state=
} | tee "$OUTPUT_DIR/process.txt"

top -l "$DURATION" -s 1 -pid "$PID" -stats pid,cpu,power \
  | tee "$OUTPUT_DIR/top.txt"

awk -v pid="$PID" '
  $1 == pid { cpu += $2; power += $3; count += 1 }
  END {
    if (count == 0) exit 1
    printf "samples=%d average_cpu=%.2f average_power=%.2f\n", count, cpu / count, power / count
  }
' "$OUTPUT_DIR/top.txt" | tee "$OUTPUT_DIR/summary.txt"

sample "$PID" "$DURATION" 10 -file "$OUTPUT_DIR/sample.txt"
echo "profile=$OUTPUT_DIR"
