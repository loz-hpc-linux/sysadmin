#!/bin/bash

# Usage: ./cpu_type.sh $XNAME

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <XNAME>"
  exit 1
fi

NODE="$1"

echo "- Checking CPU info on $NODE..."

# Try to run lscpu remotely
CPU_INFO=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$NODE" "lscpu" 2>/dev/null)

if [[ -z "$CPU_INFO" ]]; then
  echo "❌ Failed to connect to $NODE or lscpu not available."
  exit 1
fi

MODEL_NAME=$(echo "$CPU_INFO" | grep "Model name" | head -1 | awk -F: '{print $2}' | xargs)
CPU_FAMILY=$(echo "$CPU_INFO" | grep "CPU family" | awk -F: '{print $2}' | xargs)
MODEL_NUM=$(echo "$CPU_INFO" | grep -w "Model:" | awk -F: '{print $2}' | xargs)

echo "- Model name   : $MODEL_NAME"
echo "- CPU family   : $CPU_FAMILY"
echo "- Model number : $MODEL_NUM"

# Detect architecture
if [[ "$MODEL_NAME" =~ EPYC\ 7 ]]; then
  echo "- Detected: AMD EPYC 7xxx → Milan"
elif [[ "$MODEL_NAME" =~ EPYC\ 9 ]]; then
  echo "- Detected: AMD EPYC 9xxx → Genoa"
elif [[ "$CPU_FAMILY" == "25" && "$MODEL_NUM" == "1" ]]; then
  echo "- Detected: Milan (CPU Family 25, Model 1)"
elif [[ "$CPU_FAMILY" == "25" && "$MODEL_NUM" == "17" ]]; then
  echo "- Detected: Genoa (CPU Family 25, Model 17)"
else
  echo "- Unknown CPU type — manual inspection may be needed."
fi

