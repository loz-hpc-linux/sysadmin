Scipt 1 = 

exa-ncn-m001:/scratch/laurence # ./cpu_type.sh x1003c1s7b0n0
- Checking CPU info on x1003c1s7b0n0...
- Model name   : AMD EPYC 7763 64-Core Processor
- CPU family   : 25
- Model number : 1
- Detected: AMD EPYC 7xxx → Milan

Script 2 = 

functions.sh - required for the running of scripts in this repository 

Script 3 = 

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

Script 4 = 


