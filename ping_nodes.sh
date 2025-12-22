#!/bin/bash

# Help menu
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo ""
    echo "📘 Usage: $0 <XNAME>"
    echo "    Example: $0 x1102c7s2b0n2"
    echo "    Example: $0 \$XNAME"
    echo ""
    echo "🔧 Description:"
    echo "    This script pings all nodes on a blade and reports their online status."
    echo ""
    echo "📦 Required Environment Variables:"
    echo "    - \$NODES_XNAME   (used to detect if blade is Windom or Antero)"
    echo ""
    echo "🧪 Recommended:"
    echo "    Run 'setup_env.sh' before this script to populate environment vars."
    echo ""
    exit 0
fi

# Check input
if [ -z "$1" ]; then
    echo "❌ Usage: $0 <XNAME> (e.g. x1102c7s2b0n2 or x1032c4s5b1n1)"
    echo "    Run '$0 --help' for more info."
    exit 1
fi

XNAME="$1"
SLOT=${XNAME::-4}
BMC=${XNAME::-2}  # Remove final nX

# Validate required env vars
if [ -z "$NODES_XNAME" ]; then
    echo "⚠️  Environment variable \$NODES_XNAME is not set."
    echo "💡 Please run:  source setup_env.sh $XNAME"
    exit 1
fi

# Determine blade type using NODES_XNAME env variable if available
if [[ "$NODES_XNAME" == *b1n* ]]; then
    BLADE_TYPE="windom"
else
    BLADE_TYPE="antero"
fi

# Select node list based on blade type
if [[ "$BLADE_TYPE" == "windom" ]]; then
    NODES=(
        ${SLOT}b0n0
        ${SLOT}b0n1
        ${SLOT}b1n0
        ${SLOT}b1n1
    )
else
    NODES=(
        ${SLOT}b0n0
        ${SLOT}b0n1
        ${SLOT}b0n2
        ${SLOT}b0n3
    )
fi

echo "🔄 Blade Type: $BLADE_TYPE"
echo "🔍 Monitoring nodes: ${NODES[*]}"
echo

# Loop until all respond
while true; do
    ALL_UP=true
    echo "⏱️  $(date '+%F %T')"
    for NODE in "${NODES[@]}"; do
        ping -c 1 -W 1 "$NODE" &>/dev/null
        if [ $? -eq 0 ]; then
            echo "✅ $NODE is online"
        else
            echo "❌ $NODE not responding"
            ALL_UP=false
        fi
    done
    echo "------"
    if [ "$ALL_UP" = true ]; then
        echo "🎉 All nodes are online. Exiting."
        exit 0
    fi
    sleep 5
done

