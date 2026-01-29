#!/usr/bin/env bash
set -Eeuo pipefail

########## CONFIG ##########
LOG_DIR_N="/var/log/n*/current"
LOG_MESSAGES="/var/log/messages"
TAIL_LONG=20
TAIL_SHORT=10

########## HELP ##########
usage() {
cat <<'EOF'
Usage:
  log_scan_slot.sh <SLOT>

Description:
  Runs standard log scans on both sides of a slot (<SLOT>b0 and <SLOT>b1).

Requirements:
  - SSH access to SLOTb0 and SLOTb1
  - /etc/cray/nidX present
  - cluset installed

Example:
  ./log_scan_slot.sh x1102c7s2
EOF
}

########## VALIDATION ##########
fail() {
  echo "❌ $1" >&2
  exit 1
}

command -v ssh >/dev/null || fail "ssh not available"
command -v cluset >/dev/null || fail "cluset not available"
[[ -f /etc/cray/nidX ]] || fail "/etc/cray/nidX missing"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ $# -ne 1 ]] && { usage; exit 2; }

SLOT="$1"

########## LOOKUPS ##########
x2n() { awk -v k="$1" '$1==k {print $2}' /etc/cray/nidX; }
n2x() { awk -v k="$1" '$2==k {print $1}' /etc/cray/nidX; }

NID="$(x2n "$SLOT" | head -n1)"
[[ -z "$NID" ]] && fail "Unable to resolve NID for $SLOT"

XNAME="$(n2x "$NID")"
[[ -z "$XNAME" ]] && fail "Unable to resolve XNAME for NID $NID"

BMC="${XNAME::-2}"
CHASSIS="${XNAME::-6}b0"
NODES_XNAME="$(cluset -e -S, "$(n2x "$SLOT")")"
slot="${XNAME::-4}"

########## HEADER ##########
cat <<EOF

🔍 SLOT:      $SLOT
🔍 XNAME:     $NODES_XNAME
🔍 BMC:       $BMC
🔍 CHASSIS:   $CHASSIS

EOF

########## SEARCH DEFINITIONS ##########
declare -A SEARCHES=(
  ["FAILED"]="failed:$TAIL_LONG"
  ["ERROR"]="error:$TAIL_LONG"
  ["HSN"]="hsn:$TAIL_LONG"
  ["PCIe"]="PCIe:$TAIL_LONG"
  ["MCA"]="MCA:$TAIL_SHORT"
  ["MCE"]="MCE:$TAIL_SHORT"
  ["SQUASHFS"]="squashfs:$TAIL_SHORT"
  ["FAULT"]="fault:$TAIL_LONG"
  ["POWER"]="power:$TAIL_LONG"
  ["TYPE Off"]="type Off:$TAIL_LONG"
  ["TYPE On"]="type On:$TAIL_LONG"
)

########## REMOTE SCAN ##########
run_remote_scan() {
  local host="$1"

  ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" bash <<'EOF'
set -Eeuo pipefail
scan() {
  local label="$1" pattern="$2" file="$3" lines="$4"
  echo
  echo "==== $label in $file ===="
  grep -Ei "$pattern" "$file" 2>/dev/null | tail -n "$lines" || true
}

EOF
}

for side in b0 b1; do
  HOST="${SLOT}${side}"
  echo "==================== Scanning $HOST ===================="

  ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" bash <<EOF
set -Eeuo pipefail

scan() {
  local label="\$1" pattern="\$2" file="\$3" lines="\$4"
  echo
  echo "==== \$label in \$file ===="
  grep -Ei "\$pattern" "\$file" 2>/dev/null | tail -n "\$lines" || true
}

$(for key in "${!SEARCHES[@]}"; do
    IFS=: read -r pattern lines <<<"${SEARCHES[$key]}"
    echo "scan '$key' '$pattern' '$LOG_DIR_N' '$lines'"
done)

$(for key in FAILED ERROR FAULT POWER "TYPE Off" "TYPE On" PCIe; do
    IFS=: read -r pattern lines <<<"${SEARCHES[$key]}"
    echo "scan '$key' '$pattern' '$LOG_MESSAGES' '$lines'"
done)

EOF
done
