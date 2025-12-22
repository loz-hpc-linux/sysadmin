#!/usr/bin/env bash
# log_search.sh — Search remote BMC logs and show context around the LAST match
# Works with remote /bin/sh (BusyBox OK). No bash required on BMC.

set -Eeuo pipefail

DEFAULT_BEFORE=30
DEFAULT_AFTER=30

usage() {
  cat <<'EOF'
Usage:
  log_search.sh [-h] [-B <before>] [-A <after>] [-p "<pattern>"]

Description:
  - Prompts for a search pattern if -p is omitted (extended regex, case-insensitive).
  - Searches BOTH on the remote BMC:
      /var/log/messages
      /var/log/n*/current
  - Finds the LAST match across those files and prints <before>/<after> lines of context.

Options:
  -h              Show this help and exit
  -B <before>     Lines BEFORE the match (default: 30)
  -A <after>      Lines AFTER the match  (default: 30)
  -p "<pattern>"  ERE pattern (quote it if it includes | or spaces)

Environment detection:
  Requires $BMC to be set. If it's not set, run:
    source /opt/cray/hpe-admin/site-team/scripts/lharding/setup_env.sh

Examples:
  ./log_search.sh
  ./log_search.sh -p "VDDCR_CPUB|VDD_1V1_S3"
  ./log_search.sh -B 50 -A 50 -p "SensorReadError|PowerError"
EOF
}

BEFORE="$DEFAULT_BEFORE"
AFTER="$DEFAULT_AFTER"
PATTERN=""

# ---- Options ----
while getopts ":hB:A:p:" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    B) BEFORE="$OPTARG" ;;
    A) AFTER="$OPTARG" ;;
    p) PATTERN="$OPTARG" ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done

# --- Environment check ---
if [[ -z "${BMC:-}" ]]; then
  echo "ERROR: \$BMC is not set."
  echo "Please run:"
  echo "  source /opt/cray/hpe-admin/site-team/scripts/lharding/setup_env.sh"
  exit 1
fi

# --- Pattern prompt if needed ---
if [[ -z "${PATTERN}" ]]; then
  read -r -p "Enter search pattern (ERE; case-insensitive): " PATTERN
  [[ -z "${PATTERN}" ]] && { echo "No pattern provided. Aborting."; exit 1; }
fi

# --- Validate BEFORE/AFTER ---
if ! [[ "$BEFORE" =~ ^[0-9]+$ && "$AFTER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: BEFORE (-B) and AFTER (-A) must be non-negative integers."
  exit 2
fi

# Encode the pattern so the remote /bin/sh never sees metacharacters on the cmdline
if base64 --help >/dev/null 2>&1; then
  PAT_B64=$(printf '%s' "$PATTERN" | base64 -w0 2>/dev/null || printf '%s' "$PATTERN" | base64)
else
  PAT_B64=$(printf '%s' "$PATTERN" | base64)
fi

# --- Remote execution: stream script over stdin; pass args positionally (no -c) ---
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$BMC" /bin/sh -s -- "$PAT_B64" "$BEFORE" "$AFTER" <<'REMOTE'
set -eu

PAT_B64="${1:-}"
BEFORE="${2:-30}"
AFTER="${3:-30}"

# Decode pattern safely (BusyBox base64 uses -d; macOS uses -D)
if command -v base64 >/dev/null 2>&1; then
  PATTERN=$(printf '%s' "$PAT_B64" | base64 -d 2>/dev/null || printf '%s' "$PAT_B64" | base64 -D 2>/dev/null || printf '%s' "$PAT_B64")
else
  PATTERN="$PAT_B64"
fi

[ -n "$PATTERN" ] || { echo 'Remote error: Empty pattern.' >&2; exit 3; }

# Build explicit file list: /var/log/messages plus any /var/log/n*/current that exist
FILES="/var/log/messages"
for p in /var/log/n*/current; do
  [ -f "$p" ] && FILES="$FILES $p"
done

# If nothing beyond messages exists, still proceed
set -- $FILES

# Search all selected files; take the very last match globally
LAST_HIT=$(LC_ALL=C grep -HEni -- "$PATTERN" "$@" 2>/dev/null | tail -n 1 || true)

if [ -z "$LAST_HIT" ]; then
  echo 'No match found in any file.'
  exit 0
fi

# Parse "<file>:<line>:<text...>"
HIT_FILE=$(printf '%s' "$LAST_HIT" | cut -d: -f1)
HIT_LINE=$(printf '%s' "$LAST_HIT" | cut -d: -f2 | sed 's/[^0-9].*//')

# Bounds (1-based)
START=$(( HIT_LINE - BEFORE )); [ "$START" -lt 1 ] && START=1
END=$(( HIT_LINE + AFTER ))

echo
echo "=== BMC: $(hostname) ==="
echo
echo "Pattern     : $PATTERN"
echo "File        : $HIT_FILE"
echo "Match line  : $HIT_LINE"
echo "Context     : -$BEFORE / +$AFTER"
echo

# Plain context (no numbering)
sed -n "${START},${END}p" "$HIT_FILE"

echo
echo "Last 10 matching lines (global across files):"
echo
LC_ALL=C grep -HEni -- "$PATTERN" "$@" 2>/dev/null | tail -n 10 || true
REMOTE

rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Remote command failed with exit code $rc"
  exit "$rc"
fi

echo
