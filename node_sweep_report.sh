#!/bin/bash

########## Help / Usage ##########

usage() {
  cat <<'EOF'
Usage:
  node_sweep_classify.sh [OPTIONS]

Description:
  Runs sweepPBSNodes.sh, parses the output, and classifies nodes into:
    - Existing: nodes already linked to UKMET-* tickets
    - New: nodes without tickets or with NHC / communication-closed issues

  Intended for rapid triage and Slack/Jira handover prep.

Options:
  -h, --help    Show this help menu and exit

Behavior:
  - Executes: /opt/cray/hpe-admin/site-team/scripts/sweepPBSNodes.sh
  - Preserves the "Node Summary" section from the sweep output
  - Ignores nodes with a comment of 'null'
  - Classification rules:
      * UKMET-*        → Existing
      * NHC            → New
      * communication closed → New
      * anything else  → New

Requirements:
  - sweepPBSNodes.sh must be executable
  - awk, sort, mktemp must be available
  - Script must be run on a system with PBS visibility

Examples:
  ./node_sweep_classify.sh
  ./node_sweep_classify.sh --help

Notes:
  - Output is written to stdout only
  - Temporary files are cleaned up automatically
EOF
}

# Help flag
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

