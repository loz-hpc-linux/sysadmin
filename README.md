HPC Node Triage & Sweep Toolkit

A practical collection of Bash utilities for HPE Cray EX systems used to triage node failures, scan logs, validate hardware state, and summarise PBS/SAT health during incident response.

This repository is written for operators doing real incident work, not for demonstrations or automation theatre.

Prerequisites

Bash

SSH access to login nodes, compute nodes, and BMCs

/etc/cray/nidX present

cluset, jq, awk, sort

PBS visibility from login nodes

Appropriate privileges for Redfish and Cray tooling

Most scripts are expected to be run from an NCN or equivalent admin node.


Recommended Workflow

Source the environment
source setup_env.sh

Run system-wide sweeps
./run_sweeps.sh

Investigate a specific slot
./log_scan.sh x1102c7s2

Perform a targeted log search if required
./log_search.sh -p "PowerError|SensorReadError"

Validate PBS and SAT status
./status_check.sh x1102c7s2



SCRIPT REFERENCE

Script 1: cpu_type.sh — CPU Identification

  Identifies CPU model, family, and inferred generation.
  
  Example:
  ./cpu_type.sh x1003c1s7b0n0
  
  Outputs CPU model details and architecture (e.g. Milan).

Script 2: functions.sh — Shared Functions

  Core helper functions required by most scripts in this repository.
  
  This file must remain separate and must not be inlined or removed.

Script 3: log_scan.sh — Automated Slot Log Scan

  Runs standard greps across both sides of a slot (b0 and b1).
  
  Scans:
  
  /var/log/n*/current
  
  /var/log/messages
  
  Searches for common failure indicators including:
  failed, error, power, PCIe, MCE, MCA, squashfs, hsn
  
  Example:
  ./log_scan.sh x1102c7s2

Script 4: log_search.sh — Pattern-Based Log Search (BMC)

  Finds the last occurrence of a pattern and prints surrounding context.
  
  Features:
  
  Case-insensitive extended regex
  
  Configurable context lines before and after
  
  Searches both messages and n*/current logs on the BMC
  
  Requires $BMC to be set (use setup_env.sh).
  
  Examples:
  ./log_search.sh
  ./log_search.sh -p "VDDCR_CPUB|VDD_1V1_S3"
  ./log_search.sh -B 50 -A 50 -p "SensorReadError|PowerError"

Script 5: node_sweep_report.sh — PBS Node Classification

  Runs sweepPBSNodes.sh and classifies nodes into:
  
  Existing
  
  Nodes already linked to UKMET-* tickets
  
  New
  
  Nodes without tickets
  
  Nodes reporting NHC failures
  
  Nodes marked as communication closed
  
  Designed for Slack or Jira handover summaries.
  
  Example:
  ./node_sweep_report.sh

Script 6: pbs.sh — PBS Helper Functions

  PBS-related helper functions used by other scripts.
  
  Must remain separate from functions.sh.

Script 7: ping_nodes.sh — Blade-Level Ping Check

  Pings all nodes on a blade and reports reachability.
  
  Requires $NODES_XNAME (populate via setup_env.sh).
  
  Examples:
  ./ping_nodes.sh x1102c7s2b0n2
  ./ping_nodes.sh $XNAME

Script 8: run_sweeps.sh — Sweep Orchestrator

  Single-entry launcher for routine health checks.
  
  Runs in order:
  
  sweepPBSNodes.sh
  
  node_sweep_report.sh
  
  sweepCray.sh
  
  Each script is checked for executability and run with labelled output and timestamps.
  
  Examples:
  ./run_sweeps.sh
  ./run_sweeps.sh --no-color

Script 9: setup_env.sh — Environment Setup

  This script must be sourced.
  
  Example:
  source setup_env.sh
  
  Prompts for:
  
  Ticket ID
  
  NID
  
  Resolves and exports:
  
  XNAME
  
  SLOT
  
  BMC
  
  CHASSIS
  
  Node lists
  
  Optional features include readonly variable locking and a custom shell prompt.

Script 10: status_check.sh — PBS and SAT Status Check

  Checks PBS node status and SAT system state for all nodes in a slot.
  
  Requires:
  
  SYSTEM_NAME
  
  NODES_XNAME
  
  SLOT
  
  Example:
  ./status_check.sh x9000c3s0

Script 11: sweepPBSNodes.sh — PBS Filtering Engine

  Core PBS sweep logic with strict filtering rules.
  
  Key behaviour:
  
  Drops healthy nodes (free, busy, job-exclusive)
  
  Special handling for nidd and legacy nide nodes
  
  Prints state summary and formatted table
  
  Prints “Clean!” if no nodes remain after filtering
  
  Example:
  SYSTEM_NAME=exa ./sweepPBSNodes.sh

Script 12: cmm-key — CMM Key Helper

  Utility function used internally for CMM access.

Script 13: serialNumber.sh — Hardware Inventory

  Collects serial numbers and health information via Redfish.
  
  Supports CPUs, DIMMs, NodeCards, NMCs, and PSUs.
  
  Example:
  ./serialNumber.sh x1102c7s2b0n0

Script 14: hwtriage — HPE Hardware Triage Tool

  External HPE-provided diagnostic tool.
  
  Used for structured hardware checks and log collection.
  
  Example:
  /opt/clmgr/hardware-triage-tool/hwtriage -h

Script 15: hwtriage caller

  Wrapper script used to invoke hwtriage consistently.

Script 16: prepareSlot.sh — Slot Safety and Reservation

  Safety-first script used before hardware intervention.
  
  Supports actions including:
  syscheck, down, reserveNode, reserveSlot, unreserve, clean, up
  
  Example:
  ./prepareSlot.sh -a reserveSlot -x x9000c1s1b0n0 -t UKMET-1234
