#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Configuration
# =========================
PING_COUNT=1
PING_TIMEOUT=1
SLEEP_INTERVAL=5

# =========================
# Functions
# =========================
usage() {
    cat <<EOF

📘 Usage: $(basename "$0") <XNAME>
    Example: $(basename "$0") x1102c7s2b0n2
    Example: $(basename "$0") \$XNAME

🔧 Description:
    Pings all nodes on a blade until all are online.

📦 Required Environment Variables:
    - NODES_XNAME   (used to detect blade type)

🧪 Recommended:
    Run 'source setup_env.sh <XNAME>' before this script.

EOF
}

fail() {
    echo "❌ $1" >&2
    exit 1
}

detect_blade_type() {
    if [[ "$NODES_XNAME" == *"b1n"* ]]; then
        echo "windom"
    else
        echo "antero"
    fi
}

build_node_list() {
    local slot="$1"
    local blade_type="$2"

    if [[ "$blade_type" == "windom" ]]; then
        echo "${slot}b0n0 ${slot}b0n1 ${slot}b1n0 ${slot}b1n1"
    else
        echo "${slot}b0n0 ${slot}b0n1 ${slot}b0n2 ${slot}b0n3"
    fi
}

check_nodes() {
    local nodes=("$@")
    local all_up=true

    echo "⏱️  $(date '+%F %T')"
    for node in "${nodes[@]}"; do
        if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$node" &>/dev/null; then
            echo "✅ $node is online"
        else
            echo "❌ $node not responding"
            all_up=false
        fi
    done
    echo "------"

    $all_up
}

# =========================
# Main
# =========================
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

XNAME="${1:-}"
[[ -z "$XNAME" ]] && { usage; fail "XNAME is required."; }

# Validate XNAME format (basic sanity check)
if ! [[ "$XNAME" =~ ^x[0-9]+c[0-9]+s[0-9]+b[0-9]+n[0-9]+$ ]]; then
    fail "Invalid XNAME format: $XNAME"
fi

[[ -z "${NODES_XNAME:-}" ]] && fail "Environment variable NODES_XNAME is not set. Run: source setup_env.sh $XNAME"

SLOT="${XNAME%n*}"

BLADE_TYPE="$(detect_blade_type)"
read -r -a NODES <<< "$(build_node_list "$SLOT" "$BLADE_TYPE")"

echo "🔄 Blade Type: $BLADE_TYPE"
echo "🔍 Monitoring nodes: ${NODES[*]}"
echo

while true; do
    if check_nodes "${NODES[@]}"; then
        echo "🎉 All nodes are online. Exiting."
        exit 0
    fi
    sleep "$SLEEP_INTERVAL"
done
