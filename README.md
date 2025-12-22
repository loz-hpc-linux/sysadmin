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

Script 7 = PING NODES

exa-ncn-m001:/scratch/laurence # ./ping_nodes.sh -h

📘 Usage: ./ping_nodes.sh <XNAME>
    Example: ./ping_nodes.sh x1102c7s2b0n2
    Example: ./ping_nodes.sh $XNAME

🔧 Description:
    This script pings all nodes on a blade and reports their online status.

📦 Required Environment Variables:
    - $NODES_XNAME   (used to detect if blade is Windom or Antero)

🧪 Recommended:
    Run 'setup_env.sh' before this script to populate environment vars.

Script 8 = RUN SWEEPS

exa-ncn-m001:/scratch/laurence # ./run_sweeps.sh -h
Usage:
  run_sweeps.sh [OPTIONS]

Description:
  Orchestrates multiple sweep and reporting scripts, running each in sequence
  and clearly labeling their output with timestamps and status.

  Designed as a single-entry triage launcher for daily or ad-hoc health checks.

Options:
  -h, --help    Show this help menu and exit
  --no-color    Disable colored output (useful for logs or CI capture)

Executed Scripts (in order):
  1. sweepPBSNodes.sh
     - Collects PBS node state and failure summaries
  2. node_sweep_report.sh
     - Post-processes sweep results into classified output
  3. sweepCray.sh
     - Performs Cray-level health and reachability checks

Behavior:
  - Each script is checked for executability before running
  - Output is wrapped with a timestamped header
  - Exit codes are captured and reported per script
  - Execution continues even if one script fails

Requirements:
  - Bash
  - Executable permissions on all referenced scripts
  - Sufficient privileges to query PBS and Cray management services

Examples:
  ./run_sweeps.sh
  ./run_sweeps.sh --no-color
  ./run_sweeps.sh --help

Notes:
  - This script does not modify system state
  - Intended for human-readable triage, not machine parsing

Script 9 = SETUP ENVIRONMENT

exa-ncn-m001:/scratch/laurence # ./setup_env.sh -h

🔧 setup_env.sh - Node triage environment setup

Usage:
  source ./setup_env.sh

This script will:
  - Prompt for TICKET (e.g UKEMT-3555-LH) and NID(e.g nidd3493)
  - Resolve BMC, SLOT, CHASSIS, and node lists
  - Optionally apply a custom command prompt
  - Optionally lock variables as readonly
  - Export all variables for use in current session

❗ IMPORTANT: This script must be sourced to modify your current shell.
   Running it as './setup_env.sh' will NOT work as intended.

Script 10 = STATUS CHECKER  - pbs sat 

exa-ncn-m001:/scratch/laurence # ./status_check.sh -h

Usage: ./status_check.sh <SLOT>

Description:
  Checks PBS node status and SAT system state for all nodes in the given SLOT.

Requirements:
  - Run set_env.sh first to set the following variables:
      $SYSTEM_NAME, $NODES_XNAME, $SLOT
  - PBS output is fetched from the correct login node via SSH.

Example:
  ./status_check.sh x9000c3s0

Script 11 = SWEEP PBS NODES

exa-ncn-m001:/scratch/laurence # ./sweepPBSNodes.sh -h
sweepPBSNodes.sh — Scan PBS nodes and print a filtered summary.

SYNOPSIS
  sweepPBSNodes.sh
  SYSTEM_NAME must already be exported (e.g., exa, exb, exc, exd, exe, exy, exz).

WHAT IT DOES (filters applied)
  1) For nida / nib / nic / nidc / nidd / nidy / nidx prefixes (derived from SYSTEM_NAME):
     - Drop any row whose STATE list contains any of:
         free, busy, job-exclusive
       (STATE may be a comma-separated list; matching is token-aware.)

  2) Extra rule for nidd:
     - If comment equals "COLLABORATION" (case-insensitive),
       KEEP the row ONLY when state is exactly "offline" or exactly "down".
       Otherwise drop it.

  3) nide special handling (legacy panel shown when SYSTEM_NAME ends with "d"):
     - Show ONLY nide rows that contain "down" (anywhere in the row),
       EXCLUDING the converted ranges below.

EXCLUSIONS (nide ranges that were converted to nidd compute nodes)
  nide[1129-1159,1161-1191,1385-1415,1417,1641-1671]

OUTPUT
  - Prints a summary count by node state, then a formatted table:
      host switch worktype state comment
  - Prints "Clean!" if no rows survive filtering.

DEPENDENCIES
  - functions.sh (provides loginNode)
  - jq, awk, sort, ssh
  - PBS server reachable from the SSH login host

NOTES
  - The script pulls data via: ssh $(loginNode "$SYSTEM_NAME") pbsnodes -F json -a
  - Null/missing JSON fields are handled safely.
  - "job-exclusive" is matched as an exact token in the STATE list, not as a substring.

EXAMPLES
  SYSTEM_NAME=exd ./sweepPBSNodes.sh
  SYSTEM_NAME=exa ./sweepPBSNodes.sh

Script 12 = CMM KEY FUNCTION

Script 13 = SERIAL NUMBER CAPTURE

exa-ncn-m001:/opt/cray/hpe-admin/site-team/scripts # ./serialNumber.sh -h
Usage: ./serialNumber.sh [OPTIONS] xname

Options:
-h => Display this help

Script 14 = HPE CRAY - Hardware triage tool

exb-ncn-m001:~ # /opt/clmgr/hardware-triage-tool/hwtriage -h
usage: hwtriage [-h] [-r] [-n NODE_NAME] [-u USERNAME] [-p PASSWORD]
                [-l LOGPATH] [-ns {On,Off}]
                [-hw {ex235a,ex255a,ex254n,ex4252,ex425,ex235n}] [-ls]
                [-bs BEGIN_STAGE] [-rs RUN_STAGE] [-f INPUT_YAML]
                [-hy HARDWARE_YAML] [-sn] [-sno] [-k SSH_KEY] [-t TIMEOUT]
                [-v] [-cpath CUSTOM_LOG_PATH]

This is a triaging tool which checks the nodes for various issues and produces
the same on the console. It accepts nodename as the required argument and
multiple optional arguments which can be passed as needed. The description of
the arguments are displayed below.

optional arguments:
  -h, --help            show this help message and exit
  -r, --revision        Show the revision and exit.
  -n NODE_NAME, --node-name NODE_NAME
                        Enter the node name to perform the checks
  -u USERNAME, --username USERNAME
                        Username to access node controller and the redfish
                        calls
  -p PASSWORD, --password PASSWORD
                        Password to access node controller and redfish calls
  -l LOGPATH, --logpath LOGPATH
                        Provide the full log path to perform the checks
  -ns {On,Off}, --node-state {On,Off}
                        Provide the node power state
  -hw {ex235a,ex255a,ex254n,ex4252,ex425,ex235n}, --hardware {ex235a,ex255a,ex254n,ex4252,ex425,ex235n}
                        Provide the node hardware type
  -ls, --list-stages    To list stages in a yaml file
  -bs BEGIN_STAGE, --begin-stage BEGIN_STAGE
                        Enter the stage name from where the check will start
  -rs RUN_STAGE, --run-stage RUN_STAGE
                        To run only one stage from yaml file
  -f INPUT_YAML, --input-yaml INPUT_YAML
                        To pass an input config yml file as input
  -hy HARDWARE_YAML, --hardware-yaml HARDWARE_YAML
                        To pass a hardware config yml file as input
  -sn, --show-serial-number
                        To display the serial number info with the triage
                        result
  -sno, --serial-number-only
                        Collect the serial numbers into a file without
                        triaging
  -k SSH_KEY, --ssh-key SSH_KEY
                        Ssh key to enable passwordless ssh
  -t TIMEOUT, --timeout TIMEOUT
                        Timeout duration for collecting logs in seconds,
                        default=120
  -v, --verbose         To have a verbose output
  -cpath CUSTOM_LOG_PATH, --custom-log-path CUSTOM_LOG_PATH
                        Provide the custom log path to store the triage logs
                        in the case to override the default log path

Script 15 = 


