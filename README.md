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
Queries a remote compute node to identify the installed CPU architecture and processor details. 
The script connects to the specified node via SSH, runs lscpu, and extracts key information including model name, CPU family, and model number.
Using these values, the script performs simple architecture detection logic to determine whether the node is running AMD EPYC Milan or Genoa processors, which are common CPU generations in modern HPC platforms. 
The output provides a quick hardware verification check that can be useful when investigating node behaviour, validating hardware configuration, or confirming CPU generation during diagnostics.
Typical use cases include hardware verification, architecture-aware troubleshooting, and confirming node CPU types when investigating scheduler allocations or platform behaviour across heterogeneous HPC clusters.

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
Automates first-pass triage of compute nodes by running a cluster sweep and classifying nodes based on existing incident or ticket status. 
The script executes sweepPBSNodes.sh, parses the resulting node summary, and separates nodes into existing issues and new faults requiring investigation.
Nodes are classified by inspecting scheduler comments associated with each node:
Existing — nodes already linked to incident tickets
New — nodes without tickets or marked with NHC or communication closed states
The script preserves the original Node Summary output from the sweep while producing a simplified classification that can be quickly shared in Slack, operational handovers, or Jira incident updates. Temporary files are created during processing and automatically cleaned up.
Typical use cases include daily node health sweeps, incident triage, identifying newly failing nodes, and preparing operational summaries during HPC cluster support rotations.

---

### pbs.sh
Queries the PBS scheduler to retrieve and display detailed node state and metadata for one or more nodes in the cluster. 
The function connects to the appropriate login node for the target system, executes pbsnodes in JSON mode, and parses the output using jq and awk to produce a clean, tabular summary.
The output includes key infrastructure attributes such as Cray host ID, hostname, xname, switch location, CPU architecture, workload type, node state, scheduler comment, and active jobs. 
If no nodes are specified, the function returns the state of all nodes visible to the scheduler; otherwise it restricts the query to the provided node set.
Typical use cases include inspecting scheduler state during node triage, verifying resource attributes, identifying nodes that are offline or drained, and quickly correlating scheduler metadata with infrastructure issues across large HPC clusters.

---

### ping_nodes.sh
Monitors the network reachability of all compute nodes associated with a blade by repeatedly pinging each node and reporting its online status. 
The script determines the blade layout using the $NODES_XNAME environment variable and automatically selects the correct node pattern for either Windom or Antero blades.
Once the node list is derived from the provided xname, the script continuously checks each node using ICMP ping and prints a live status summary indicating whether nodes are responding. 
The loop continues until all nodes on the blade become reachable, making it useful for tracking node recovery during power operations, boot sequences, or maintenance work.
Typical use cases include monitoring node availability during blade bring-up, verifying cluster recovery after maintenance, and confirming that all nodes within a slot have returned to network reachability.

---

### setup_env.sh
Initialises a structured troubleshooting environment for investigating node issues within an HPC cluster. 
The script prompts the operator for a ticket identifier and node NID, then resolves related infrastructure information such as the node xname, BMC address, slot, chassis, and associated nodes within the same blade.
When sourced into the current shell session, the script exports a set of environment variables that standardise the investigation context and make it easier for other diagnostic scripts to operate without repeatedly resolving infrastructure metadata. 
It also loads shared utility functions, updates the $PATH to include common operational tooling, and optionally applies a custom command prompt to visually indicate an active triage session.
Additional safeguards allow the user to lock the environment variables as readonly to prevent accidental modification during troubleshooting.
Typical use cases include incident response, node triage sessions, infrastructure debugging workflows, and preparing a consistent shell environment for running cluster diagnostic scripts.

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
