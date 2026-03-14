#!/bin/bash

set -u

SWEEP_SCRIPT="${SWEEP_SCRIPT:-/opt/hpc-tools/bin/cluster_sweep.sh}"

########## Help / Usage ##########

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [OPTIONS]

Description:
  Runs cluster_sweep.sh, parses the output, and classifies nodes into:
    - Existing: nodes already linked to INC-* tickets
    - New: nodes without tickets or with health-check / communication-closed issues

  Intended for rapid triage and chat/ticket handover prep.

Options:
  -h, --help    Show this help menu and exit

Behavior:
  - Executes: ${SWEEP_SCRIPT}
  - Preserves the "Node Summary" section from the sweep output
  - Ignores nodes with a comment of 'null'
  - Classification rules:
      * INC-*                        -> Existing
      * health check                 -> New
      * communication closed         -> New
      * anything else                -> New

Requirements:
  - cluster_sweep.sh must be executable
  - awk, sort, mktemp must be available
  - Script must be run on a system with PBS visibility

Examples:
  $(basename "$0")
  $(basename "$0") --help

Notes:
  - Output is written to stdout only
  - Temporary files are cleaned up automatically
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  rm -f "${TMP_OUTPUT:-}" "${EXISTING_TMP:-}" "${NEW_TMP:-}"
}

########## Arg Parsing ##########

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  -*)
    usage
    die "Unknown option: $1"
    ;;
esac

########## Preflight Checks ##########

command -v awk >/dev/null 2>&1 || die "Missing required command: awk"
command -v sort >/dev/null 2>&1 || die "Missing required command: sort"
command -v mktemp >/dev/null 2>&1 || die "Missing required command: mktemp"

[[ -x "$SWEEP_SCRIPT" ]] || die "Sweep script is not executable: $SWEEP_SCRIPT"

TMP_OUTPUT="$(mktemp)"
EXISTING_TMP="$(mktemp)"
NEW_TMP="$(mktemp)"
trap cleanup EXIT INT TERM

########## Run Sweep ##########

"$SWEEP_SCRIPT" > "$TMP_OUTPUT"

########## Print Header / Node Summary ##########

awk '
  /^System:/ { sys=$0 }
  /^Node Summary:/ { ns=1; print; next }
  ns==1 && NF==0 { ns=0 }
  ns==1 { print }
' "$TMP_OUTPUT"

echo
echo "----------------------------------------------------------------------------------"

########## Classify Nodes ##########

awk -v existing_file="$EXISTING_TMP" -v new_file="$NEW_TMP" '
  /^[^ ]+ +x[0-9]+c[0-9]+r[0-9]+/ {
    nid=$1
    comment=""

    for (i=5; i<=NF; i++) {
      comment = comment $i " "
    }

    sub(/[ \t]+$/, "", comment)

    if (comment == "null") {
      next
    }

    if (comment ~ /INC-/) {
      printf "%s - %s\n", nid, comment >> existing_file
    } else if (comment ~ /health check/ || comment ~ /node down: communication closed/) {
      printf "%s - %s\n", nid, comment >> new_file
    } else {
      printf "%s - %s\n", nid, comment >> new_file
    }
  }
' "$TMP_OUTPUT"

########## Output Sections ##########

echo "Existing:"
if [[ -s "$EXISTING_TMP" ]]; then
  sort -u "$EXISTING_TMP"
fi

echo
echo "New:"
if [[ -s "$NEW_TMP" ]]; then
  cat "$NEW_TMP"
fi

echo "----------------------------------------------------------------------------------"
