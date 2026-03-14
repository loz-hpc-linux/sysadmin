#!/bin/bash

# Toggle for coloured output
USE_COLOURS=true

# Colour codes
if $USE_COLOURS; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  YELLOW='\033[1;33m'
  NC='\033[0m' # No Colour
else
  GREEN=''
  RED=''
  BLUE=''
  YELLOW=''
  NC=''
fi

# Separator
function separator() {
  echo -e "${YELLOW}\n============================================================"
  echo -e "$1 - $(date)"
  echo -e "============================================================${NC}"
}

# Run and label output
function run_and_label() {
  local label="$1"
  local script_path="$2"

  if [[ -x "$script_path" ]]; then
    separator "$label"
    "$script_path"
    local status=$?
    if [[ $status -ne 0 ]]; then
      echo -e "${RED}[ERROR] $label failed with exit code $status${NC}"
    else
      echo -e "${GREEN}[SUCCESS] $label completed${NC}"
    fi
  else
    echo -e "${RED}[ERROR] $label not found or not executable: $script_path${NC}"
  fi
}

# === RUN SCRIPTS ===
run_and_label "Scheduler Sweep" "/opt/hpc-tools/bin/scheduler_sweep.sh"
run_and_label "Node Sweep Report" "/var/tmp/hpc/node_sweep_report.sh"
run_and_label "Cluster Sweep" "/opt/hpc-tools/bin/cluster_sweep.sh"

echo -e "${BLUE}\nAll tasks completed. Review the above output for results.${NC}"
