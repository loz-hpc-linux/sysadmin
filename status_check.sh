#!/bin/bash

# ----------------------------------------
# status_check.sh - PBS & SAT status checker for a given SLOT
# ----------------------------------------

# 📘 Help Menu
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo -e "\nUsage: ./status_check.sh <SLOT>\n"
  echo "Description:"
  echo "  Checks PBS node status and SAT system state for all nodes in the given SLOT."
  echo
  echo "Requirements:"
  echo "  - Run set_env.sh first to set the following variables:"
  echo "      \$SYSTEM_NAME, \$NODES_XNAME, \$SLOT"
  echo "  - PBS output is fetched from the correct login node via SSH."
  echo
  echo "Example:"
  echo "  ./status_check.sh x9000c3s0"
  exit 0
fi

# 🎯 SLOT Input
SLOT="$1"
if [[ -z "$SLOT" ]]; then
  echo "❌ Error: SLOT argument missing."
  echo "Run './status_check.sh --help' for usage."
  exit 1
fi

# ✅ Required environment variables
REQUIRED_VARS=(SYSTEM_NAME NODES_XNAME SLOT)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "❌ Error: Environment variable \$$var is not set."
    echo "Please run set_env.sh first."
    exit 1
  fi
done

if [[ ! -f /scratch/laurence/pbs.sh ]]; then
  echo "❌ Error: Required file 'pbs.sh' not found in /scratch/laurence/"
  exit 1
fi

# 🧪 Start Check
echo -e "\n🔍 Checking status for SLOT: $SLOT"
echo "------------------------------------------"

# ✅ PBS Output
echo -e "\n📦 PBS Status:"
echo -e "ℹ️  Querying PBS for nodes: $NODES_XNAME"
echo
source /scratch/laurence/pbs.sh
pbs | grep $SLOT
echo

# ✅ SAT Output
echo -e "\n🛰 SAT Status:"
sat status --filter xname="${SLOT}b*" --fields xname,aliases,role,subrole,state,enabled,net,boot,desired,configuration

echo -e "\n✅ Done.\n"
