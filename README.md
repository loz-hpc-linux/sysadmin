Scipt 1 = CPU TYPE

exa-ncn-m001:/scratch/laurence # ./cpu_type.sh x1003c1s7b0n0
- Checking CPU info on x1003c1s7b0n0...
- Model name   : AMD EPYC 7763 64-Core Processor
- CPU family   : 25
- Model number : 1
- Detected: AMD EPYC 7xxx → Milan

Script 2 = FUNCTIONS

functions.sh - required for the running of scripts in this repository 

Script 3 = AUTO LOG SCAN

exa-ncn-m001:/scratch/laurence # ./log_scan.sh -h
Usage:
  log_scan_slot.sh <SLOT>

Description:
  Runs a set of standard greps over /var/log/n*/current and /var/log/messages
  on both sides of a slot (<SLOT>b0 and <SLOT>b1) via SSH.

Arguments:
  SLOT          Slot identifier that resolves via /etc/cray/nidX
                Example: x1102c7s2  (script will SSH to x1102c7s2b0 and x1102c7s2b1)

Options:
  -h, --help    Show this help menu and exit

Notes:
  - Requires SSH access to ${SLOT}b0 and ${SLOT}b1.
  - Uses /etc/cray/nidX for xname<->nid lookups.
  - cluset must be available for the NODES_* expansions.

Examples:
  ./log_scan_slot.sh x1102c7s2

Script 4 = LOG SEARCH USING PATTERN

exa-ncn-m001:/scratch/laurence # ./log_search.sh -h
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

Script 5 = NODE SWEEP REPORT (PBS)

exa-ncn-m001:/scratch/laurence # ./node_sweep_report.sh -h
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

Script 6 = PBS FUNCTION (required for other scripts - has to be separate to functions.sh)

Script 7 = 
