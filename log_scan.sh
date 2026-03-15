#!/bin/bash

#set -euo pipefail

readonly NODE_MAP_FILE="${NODE_MAP_FILE:-/etc/hpc/node-map}"

########## Help / Usage ##########

usage() {
  cat <<'EOF'
Usage:
  log_scan_slot.sh <SLOT>

Description:
  Runs a set of standard greps over /var/log/n*/* and /var/log/messages
  on both sides of a slot (<SLOT>b0 and <SLOT>b1) via SSH.

Arguments:
  SLOT          Slot identifier that resolves via the node mapping file
                Example: $SLOT  (script will SSH to ${Slot}b0 and ${SLOT}b1)

Options:
  -h, --help    Show this help menu and exit

Notes:
  - Requires SSH access to ${SLOT}b0 and ${SLOT}b1.
  - Uses /etc/hpc/node-map for xname<->nid lookups.
  - cluset must be available for the NODES_* expansions.

Examples:
  ./log_scan_slot.sh $SLOT
EOF
}

# Help flag
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# Arg check
if [[ $# -lt 1 ]] || [[ -z "${1:-}" ]]; then
  usage
  exit 2
fi

SLOT="$1"

########## Functions ##########

x2n() {
  grep "$1" "${NODE_MAP_FILE}" | awk '{print $2}'
}

n2x() {
  grep "$1" "${NODE_MAP_FILE}" | awk '{print $1}'
}

run_search() {
  local desc="$1"
  local cmd="$2"
  echo
  echo "==================== $desc ===================="
  eval "$cmd"
}

########## OUTPUT HEADER ##########

echo
echo "🔍 SLOT:     "
echo "$SLOT"
echo

# Derive the affected node's XNAME from NID
readonly NID=$(x2n "$SLOT" | head -n1)
readonly XNAME=$(n2x "$NID")
readonly BMC=${XNAME::-2}
readonly CHASSIS="${XNAME::-6}b0"
readonly NODES_XNAME=$(cluset -e -S, $(n2x $SLOT))
readonly NODES_NID=$(cluset -e -S, $(x2n $SLOT))
readonly NODES_NID_LIST=$(cluset -e $(x2n $SLOT))
readonly slot=${XNAME::-4}

echo "🔍 XNAME:    "
echo "$NODES_XNAME"
echo

echo "🔍 BMC:      "
echo "$BMC"
echo

echo "🔍 CHASSIS:  "
echo "$CHASSIS"
echo

########## LOG SEARCHES ##########

for side in b0 b1; do
  run_search "FAILED in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'failed' /var/log/n*/* | tail -n 20\""
  run_search "ERROR in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'error' /var/log/n*/* | tail -n 20\""
  run_search "HSN in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'hsn' /var/log/n*/* | tail -n 20\""
  run_search "PCIe in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'PCIe' /var/log/n*/* | tail -n 20\""
  run_search "MCA in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'MCA' /var/log/n*/* | tail -n 10\""
  run_search "MCE in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'MCE' /var/log/n*/* | tail -n 10\""
  run_search "SQUASHFS in /var/log/n*/* on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'squashfs' /var/log/n*/* | tail -n 10\""

  run_search "FAILED in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'failed' /var/log/messages | tail -n 20\""
  run_search "ERROR in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'error' /var/log/messages | tail -n 20\""
  run_search "FAULT in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'fault' /var/log/messages | tail -n 20\""
  run_search "POWER in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'power' /var/log/messages | tail -n 20\""
  run_search "TYPE Off in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'type Off' /var/log/messages | tail -n 20\""
  run_search "TYPE On in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'type On' /var/log/messages | tail -n 20\""
  run_search "PCIe in /var/log/messages on ${SLOT}${side}" "ssh ${SLOT}${side} \"grep -Ei 'PCIe' /var/log/messages | tail -n 20\""
done
