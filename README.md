# HPC Node Diagnostics Toolkit

A collection of Bash utilities designed to assist with diagnosing and triaging node issues in large-scale Linux HPC clusters.

The toolkit focuses on rapid infrastructure investigation by automating common operational tasks such as log analysis, node classification, scheduler state inspection, and hardware information gathering.

These scripts were originally developed to streamline troubleshooting workflows across distributed HPC environments.

---

## Features

• Remote CPU and hardware identification  
• Node connectivity and availability checks  
• Automated log scanning across nodes and BMC interfaces  
• PBS scheduler node state parsing and reporting  
• Node sweep classification to assist incident triage  
• Environment setup for structured debugging sessions  

---

## Scripts

### cpu_type.sh
Queries CPU information on a remote node using SSH and extracts key processor details such as model name, family, and model number.

Useful for verifying hardware configuration across compute nodes.

---

### functions.sh
Shared utility library used by the HPC diagnostics scripts to simplify common operational tasks on HPE Cray EX systems. 
The file provides reusable functions for xname validation and parsing, node and slot translation, scheduler interaction, Redfish API queries, BMC credential retrieval, and reservation management.
The library standardises many routine tasks performed during cluster troubleshooting, including:
Validating and parsing Cray xname identifiers (cabinet, chassis, slot, node, and BMC formats).
Translating between NIDs and xnames using /etc/cray/nidX.
Querying node state and metadata from PBS scheduler (pbsnodes).
Automating node operations such as offline/online actions, comments, and reservation management.
Discovering and selecting available login nodes for scheduler interaction.
Identifying CPU architecture types (e.g. Milan vs Genoa) for targeted diagnostics.
Performing Redfish API queries against node BMCs for hardware telemetry access.
Retrieving BMC credentials via Cray SCSD services.
Determining slot relationships such as sibling nodes and BMC mappings.
These functions act as a common operational toolkit for higher-level scripts, enabling consistent interaction with cluster infrastructure components including compute nodes, BMCs, the scheduler, and system management services.
Typical use cases include node triage, hardware fault investigation, scheduler state inspection, cluster maintenance operations, and automated diagnostics workflows across large-scale Linux HPC environments.

---

### log_scan.sh
Runs a standard set of targeted log searches across both BMC sides of a slot (<SLOT>b0 and <SLOT>b1) over SSH to speed up first-pass HPC triage. 
The script resolves related xname/NID information from /etc/cray/nidX, prints useful slot context (xnames, BMC, chassis), and scans both /var/log/n*/current and /var/log/messages for common failure indicators, 
such as failed, error, fault, power, HSN, PCIe, MCA, MCE, squashfs, and node power state markers (type Off / type On). 
Results are grouped by log type and slot side, with recent matches shown via tail, making it useful for quickly spotting hardware, boot, fabric, filesystem, and power-related issues across an entire slot.

---

### log_search.sh
Searches remote Cray BMC logs for a user-defined pattern and returns contextual output around the most recent match. 
The script connects to the target BMC via SSH, scans /var/log/messages and /var/log/n*/current, and identifies the last occurrence of the search pattern across all logs. 
It then prints configurable lines of context before and after the match, helping operators quickly understand the surrounding events during hardware or node fault investigation.

The script supports extended regular expressions, prompts for a pattern if one is not supplied, and encodes the search pattern to safely execute against minimal remote shells 
(including BusyBox environments commonly found on BMC systems). It also performs environment checks to ensure the correct BMC target is set and automatically handles file discovery across node log paths.

Typical use cases include diagnosing power faults, sensor errors, node crashes, hardware telemetry events, and boot failures by quickly locating the most recent relevant log entry and its surrounding context.

---

### node_sweep_report.sh
Parses PBS node sweep output and classifies nodes into actionable categories.

Example classifications:

• Nodes already linked to active incident tickets  
• Newly detected faults requiring investigation  
• Nodes with closed communication or NHC issues  

Useful for generating quick triage reports for operational handovers.

---

### pbs.sh
Fetches PBS node information in JSON format and formats key attributes such as:

• node hostname  
• xname  
• switch location  
• core type  
• work type  
• node state  
• associated jobs  

Useful for inspecting scheduler state across a node set.

---

### ping_nodes.sh
Checks connectivity across nodes within a blade or slot.

Reports reachability and assists in identifying partially failing hardware groups.

---

### setup_env.sh
Initialises a debugging environment for node triage sessions.

Handles:

• ticket identifiers  
• node ID resolution  
• environment variables  
• shell prompt context  

---

### status_check.sh
Checks both PBS node status and system health state for nodes within a specified slot.

Provides a quick operational snapshot for infrastructure engineers.

---

## Requirements

• Linux environment  
• SSH access to compute nodes  
• jq (for PBS JSON parsing)  
• Access to cluster management utilities where applicable

---

## Example Workflow

Typical investigation flow:

1. Initialise ENVIRONMENT (Variables, paths, command prompt) 

source setup_env.sh

2. Inspect node status (PBS & SAT) 

./status_check.sh x1102c7s2

3. Scan logs (latest keyword results) 

./log_scan.sh x1102c7s2

4. Search BMC logs (specific string search to capture period of interest) 

./log_search.sh -p "error" -A 50 -B 50

---

## Purpose

These tools were created to improve the efficiency of diagnosing infrastructure issues in distributed Linux HPC environments by reducing repetitive manual investigation tasks.

---

## License

MIT
