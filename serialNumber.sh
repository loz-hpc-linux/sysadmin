#!/bin/bash
#
############# GOAL #############
# Collect serial numbers from nodes and switches
################################
# Created by Thiago Carvalho <thiago.carvalho@hpe.com> heavily inspired in Pete Custerson <pete.custerson@hpe.com> script
################################
######## Test cases #######
# - Genoa BMC: x9000c3s0b0
# - Genoa Node: x9000c3s0b0n0
# - Milan BMC: x9000c1s2b1
# - Milan Node: x9000c1s2b1n1
# - Mountain Switch:
# - River BMC: x3107c0s13b0
# - River Node: x3107c0s13b0n0
# - River Switch:
################################

set -euo pipefail

########## Functions ###########

readonly BASE_DIR="$(dirname ${0})"
source "${BASE_DIR}/functions.sh"

fetchMountainNodeCard() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local nodeNumber="${4}"
    local uri="Systems/Node${nodeNumber}"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local partNumber=$(echo $output | jq -r '.PartNumber')
    local health="$(echo $output | jq -r '.Status.Health')"
    local version="$(echo $output | jq -r '.BiosVersion')"
    local model="$(echo "${output}" | jq -r '.Model')"
    printf "\t\t%-13s %-18s %-18s %-35s %-11s %s\n" \
            "NodeCard" "${serialNumber}" "${partNumber}" "${model}" "${health}" "${version}"
}

fetchMountainNodeCPU() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local nodeNumber="${4}"
    local uri="Systems/Node${nodeNumber}/Processors"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local cpus=$(echo $output | jq -r '.Members[] | .["@odata.id"]')
    local sorted_cpus=$(echo "$cpus" | sort -V)
    printf "${BOLD}\tProcessors\n${RESET}"
    printf "${BOLD}\t\t%-8s %-8s %-34s %-9s %-13s %-14s %-18s %-11s %s\n${RESET}" \
            "ID" "Health" "Processor" "Cores" "Threads" "SerialNumber" "Speed" "Socket"
    for fullURI in $sorted_cpus; do
        local uri="$(echo "${fullURI}" | sed -e 's#/redfish/v1/##g')"
        local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
        local id="$(echo $output | jq -r '.Id')"
        local health="$(echo $output | jq -r '.Status.Health')"
        local model="$(echo $output | jq -r '.Model')"
        local speed_mhz="$(echo $output | jq -r '.MaxSpeedMHz')"
        local serialNumber="$(echo $output | jq -r '.SerialNumber')"
        local socket="$(echo $output | jq -r '.Socket')"
        local cores="$(echo $output | jq -r '.TotalCores')"
        local threads="$(echo $output | jq -r '.TotalThreads')"
        printf "\t\t%-8s %-8s %-34s %-9s %-13s %-14s %-18s %-11s %s\n" \
            "${id}" "${health}" "${model}" "${cores}" "${threads}" "${serialNumber}" "${speed_mhz}" "${socket}"
    done
}

fetchMountainNodeNMC() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local nodeNumber="${4}"
    local uri="Chassis/Node${nodeNumber}/NetworkAdapters/HPCNet0"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local partNumber="$(echo $output | jq -r '.PartNumber')"
    local model="$(echo $output | jq -r '.Model')"
    case "${nodeNumber}" in
        0|1)
            local mezz=0
            ;;
        2|3)
            local mezz=2
            ;;
        *)
            die "Unexpected node number ${nodeNumber}"
            ;;
    esac
    local uri="Chassis/Mezz${mezz}"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local health="$(echo $output | jq -r '.Status.Health')"
    local uri="UpdateService/FirmwareInventory/Node${nodeNumber}.HPCNet0"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local version="$(echo $output | jq -r '.Version')"
    printf "\t\t%-13s %-18s %-18s %-35s %-11s %s\n" \
            "NMC" "${serialNumber}" "${partNumber}" "${model}" "${health}" "${version}"

}

fetchMountainNodeMemory() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local nodeNumber="${4}"
    local uri="Systems/Node${nodeNumber}/Memory"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local dimms=$(echo $output | jq -r '.Members[] | .["@odata.id"]')
    local sortedDIMMs=$(echo "$dimms" | sort -V)
    printf "${BOLD}\tMemory\n${RESET}"
    printf "${BOLD}\t\t%-15s %-8s %-14s %-8s %-18s %-11s %-11s %s\n${RESET}" \
            "ID" "Health" "Manufacturer" "Type" "SerialNumber" "Size (mb)" "Speed" "Location"
    for fullURI in $sortedDIMMs; do
        local uri="$(echo "${fullURI}" | sed -e 's#/redfish/v1/##g')"
        local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
        local id="$(echo $output | jq -r '.Id')"
        local manufacturer=$(echo $output | jq -r '.Manufacturer')
        local type=$(echo $output | jq -r '.MemoryDeviceType')
        local speed=$(echo $output | jq -r '.OperatingSpeedMhz')
        local serialNumber="$(echo $output | jq -r '.SerialNumber')"
        local location=$(echo $output | jq -r '.MemoryLocation | "Slot: \(.Slot), Socket: \(.Socket)"')
        local health="$(echo $output | jq -r '.Status.State')"
        local size="$(echo "${output}" | jq -r '.CapacityMiB')"
        printf "\t\t%-15s %-8s %-14s %-8s %-18s %-11s %-11s %s\n" \
            "${id}" "${health}" "${manufacturer}" "${type}" "${serialNumber}" "${size}" "${speed}" "${location}"
    done
}

fetchMountainNodePowerSupply() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local nodeNumber="${4}"
    local uri="Chassis/Node${nodeNumber}/PowerSubsystem/PowerSupplies/PowerSupply0"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local model="$(echo $output | jq -r '.Model')"
    local health="$(echo $output | jq -r '.Status.Health')"
    local version="$(echo $output | jq -r '.Version')"
    printf "\t\t%-13s %-18s %-18s %-35s %-11s %s\n" \
            "PowerSupply" "${serialNumber}" "-" "${model}" "${health}" "${version}"
}

fetchMountainSwitch() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local uri="Chassis/Enclosure"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local health="$(echo $output | jq -r '.Status.Health')"
    local partNumber="$(echo $output | jq -r '.PartNumber')"
    printf "\t\t%-13s %-18s %-18s %-35s %-11s %s\n" \
            "Motherboard" "${serialNumber}" "${partNumber}" "-" "${health}" "-"
}

fetchRiverNodeCard() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local uri="Systems/1"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local biosVersion="$(echo $output | jq -r '.BiosVersion')"
    local model="$(echo $output | jq -r '.Model')"
    local health="$(echo $output | jq -r '.Status.Health')"
    printf "\t\t%-13s %-18s %-18s %-35s %-11s %s\n" \
            "NodeCard" "${serialNumber}" "-" "${model}" "${health}" "${biosVersion}"
}

fetchRiverNodeCPU() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local uri="Systems/1/Processors"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local cpus=$(echo $output | jq -r '.Members[] | .["@odata.id"]')
    local sorted_cpus=$(echo "$cpus" | sort -V)
    printf "${BOLD}\tProcessors\n${RESET}"
    printf "${BOLD}\t\t%-8s %-8s %-34s %-9s %-13s %-14s %-18s %-11s %s\n${RESET}" \
            "ID" "Health" "Processor" "Cores" "Threads" "SerialNumber" "Speed" "Socket"
    for fullURI in $sorted_cpus; do
        local uri="$(echo "${fullURI}" | sed -e 's#/redfish/v1/##g')"
        local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
        local id="$(echo $output | jq -r '.Id')"
        local health="$(echo $output | jq -r '.Status.Health')"
        local model="$(echo $output | jq -r '.Model')"
        local speed_mhz="$(echo $output | jq -r '.MaxSpeedMHz')"
        local serialNumber="$(echo $output | jq -r '.SerialNumber')"
        local socket="$(echo $output | jq -r '.Socket')"
        local cores="$(echo $output | jq -r '.TotalCores')"
        local threads="$(echo $output | jq -r '.TotalThreads')"
        printf "\t\t%-8s %-8s %-34s %-9s %-13s %-14s %-18s %-11s %s\n" \
            "${id}" "${health}" "${model}" "${cores}" "${threads}" "${serialNumber}" "${speed_mhz}" "${socket}"
    done
}

fetchRiverNodeMemory() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local uri="Systems/1/Memory"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local dimms=$(echo $output | jq -r '.Members[] | .["@odata.id"]')
    local sortedDIMMs=$(echo "$dimms" | sort -V)
    printf "${BOLD}\tMemory\n${RESET}"
    printf "${BOLD}\t\t%-15s %-8s %-14s %-8s %-18s %-11s %-11s %s\n${RESET}" \
            "ID" "Health" "Manufacturer" "Type" "SerialNumber" "Size (mb)" "Speed" "Location"
    for fullURI in $sortedDIMMs; do
        local uri="$(echo "${fullURI}" | sed -e 's#/redfish/v1/##g')"
        local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
        local id="$(echo $output | jq -r '.Id')"
        local manufacturer=$(echo $output | jq -r '.Manufacturer')
        local type=$(echo $output | jq -r '.MemoryDeviceType')
        local speed=$(echo $output | jq -r '.OperatingSpeedMhz')
        local serialNumber="$(echo $output | jq -r '.SerialNumber')"
        local location=$(echo $output | jq -r '.MemoryLocation | "Slot: \(.Slot), Socket: \(.Socket)"')
        local health="$(echo $output | jq -r '.Status.State')"
        local size="$(echo "${output}" | jq -r '.CapacityMiB')"
        printf "\t\t%-15s %-8s %-14s %-8s %-18s %-11s %-11s %s\n" \
            "${id}" "${health}" "${manufacturer}" "${type}" "${serialNumber}" "${size}" "${speed}" "${location}"
    done
}

fetchRiverNodeStatus() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local uri="Systems/1"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local hardware=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.BiosOrHardwareHealth.Status.Health')
    local fans=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.Fans.Status.Health')
    local memory=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.Memory.Status.Health')
    local ps=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.PowerSupplies.Status.Health')
    local network=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.Network.Status.Health')
    local procs=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.Processors.Status.Health')
    local storage=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.Storage.Status.Health')
    local temperatures=$(echo $output | jq -r '.Oem.Hpe.AggregateHealthStatus.Temperatures.Status.Health')
    printf "\t\t%-13s %-18s %-18s %-35s %-11s %-13s %-13s %-13s %s\n" \
            "${hardware}" "${fans}" "${memory}" "${ps}" "${network}" "${procs}" "${storage}" "${temperatures}"
}

fetchCMM() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local uri="Chassis/Enclosure"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local health="$(echo $output | jq -r '.Status.Health')"
    local partNumber="$(echo $output | jq -r '.PartNumber')"
    printf "\t%-13s %-18s %-18s %-35s %-11s %s\n" \
            "Motherboard" "${serialNumber}" "${partNumber}" "-" "${health}" "-"
}

fetchCMMPowerSupplyRectifier() {
    local bmc="${1}"
    local bmcUsername="${2}"
    local bmcPassword="${3}"
    local rectifier="${4}"
    local uri="Chassis/Enclosure/PowerSubsystem/PowerSupplies/Rectifier${rectifier}"
    local output="$(redfishGET "${bmc}" "${bmcUsername}" "${bmcPassword}" "${uri}")"
    local serialNumber="$(echo $output | jq -r '.SerialNumber')"
    local health="$(echo $output | jq -r '.Status.Health')"
    local version="$(echo $output | jq -r '.Version')"
    printf "\t%-13s %-18s %-11s %-7s\n" \
            "Rectifier" "${serialNumber}" "${health}" "${version}"
}

usage() {
        die """Usage: $0 [OPTIONS] xname

Options:
-h => Display this help
"""
}

################################

#### Main script execution #####

if [[ "$#" -lt 1 ]]; then
    usage
fi

while getopts "h" option; do
    case $option in
        h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

readonly XNAME="$1"
test "${XNAME}" = "help" && usage
if checkNodeXname "${XNAME}"; then
    readonly SLOT="$(parseSlotXname "${XNAME}")"
    printf "${BOLD}${SLOT}${RESET}\n"
    readonly CABINET="$(parseCabinetXname "${XNAME}")"
    case "${CABINET}" in
        x9|x1)
            readonly NID="$(xton "${XNAME}")"
            if isGenoa "${NID}"; then
                bmc="${SLOT}b0"
                bmcUsername=$(scsdBMCUsername "${bmc}")
                bmcPassword=$(scsdBMCPassword "${bmc}")
                printf "\t${BOLD}${bmc}${RESET} (nC0) (n0/n1)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                printf "\t${BOLD}${bmc}${RESET} (nC1) (n2/n3)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 2
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 2
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 2
            elif isMilan "${NID}"; then
                bmc="${SLOT}b0"
                bmcUsername=$(scsdBMCUsername "${bmc}")
                bmcPassword=$(scsdBMCPassword "${bmc}")
                printf "\t${BOLD}${bmc}${RESET} (nC0) (n0/n1)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 1
                bmc="${SLOT}b1"
                bmcUsername=$(scsdBMCUsername "${bmc}")
                printf "\t${BOLD}${bmc}${RESET} (nC1) (n0/n1)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 1
            else
                die "Cannot figure out if node is milan or genoa"
            fi
            printf "${BOLD}${XNAME}${RESET}\n"
            bmc="$(parseBMCXname "${XNAME}")"
            bmcUsername=$(scsdBMCUsername "${bmc}")
            bmcPassword=$(scsdBMCPassword "${bmc}")
            nodeNumber="$(parseNodeNumber "${XNAME}")"
            fetchMountainNodeCPU "${bmc}" "${bmcUsername}" "${bmcPassword}" "${nodeNumber}"
            fetchMountainNodeMemory "${bmc}" "${bmcUsername}" "${bmcPassword}" "${nodeNumber}"
            ;;
        x3)
            bmc="$(parseBMCXname "${XNAME}")"
            bmcUsername=$(scsdBMCUsername "${bmc}")
            bmcPassword=$(scsdBMCPassword "${bmc}")
            printf "\t${BOLD}${bmc}n0${RESET}\n"
            printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
            fetchRiverNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}"
            printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %-13s %-13s %-13s %s\n${RESET}" \
                    "Hardware" "Fans" "Memory" "PowerSupplies" "Network" "Processors" "Storage" "Temperatures"
            fetchRiverNodeStatus "${bmc}" "${bmcUsername}" "${bmcPassword}"
            fetchRiverNodeCPU "${bmc}" "${bmcUsername}" "${bmcPassword}"
            fetchRiverNodeMemory "${bmc}" "${bmcUsername}" "${bmcPassword}"
            ;;
        *)
            die "Unkown cabinet ${CABINET}"
            ;;
    esac
elif checkNodeBMCXname "${XNAME}"; then
    readonly SLOT="$(parseSlotXname "${XNAME}")"
    printf "${BOLD}${SLOT}${RESET}\n"
    readonly CABINET="$(parseCabinetXname "${XNAME}")"
    case "${CABINET}" in
        x9|x1)
            readonly NID="$(xton "${XNAME}n0")"
            if isGenoa "${NID}"; then
                bmc="${SLOT}b0"
                bmcUsername=$(scsdBMCUsername "${bmc}")
                bmcPassword=$(scsdBMCPassword "${bmc}")
                printf "\t${BOLD}${bmc}${RESET} (nC0) (n0/n1)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                printf "\t${BOLD}${bmc}${RESET} (nC1) (n2/n3)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 2
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 2
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 2
            elif isMilan "${NID}"; then
                bmc="${XNAME}"
                nC="${XNAME: -1}"
                bmcUsername=$(scsdBMCUsername "${bmc}")
                bmcPassword=$(scsdBMCPassword "${bmc}")
                printf "\t${BOLD}${bmc}${RESET} (nC${nC}) (n0/n1)\n"
                printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
                fetchMountainNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodeNMC "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 0
                fetchMountainNodePowerSupply "${bmc}" "${bmcUsername}" "${bmcPassword}" 1
            else
                die "Cannot figure out if bmc is milan or genoa"
            fi
            ;;
        x3)
            bmc="$(parseBMCXname "${XNAME}")"
            bmcUsername=$(scsdBMCUsername "${bmc}")
            bmcPassword=$(scsdBMCPassword "${bmc}")
            printf "\t${BOLD}${bmc}n0${RESET}\n"
            printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
            fetchRiverNodeCard "${bmc}" "${bmcUsername}" "${bmcPassword}"
            printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %-13s %-13s %-13s %s\n${RESET}" \
                    "Hardware" "Fans" "Memory" "PowerSupplies" "Network" "Processors" "Storage" "Temperatures"
            fetchRiverNodeStatus "${bmc}" "${bmcUsername}" "${bmcPassword}"
            ;;
        *)
            die "Unkown cabinet ${CABINET}"
            ;;
    esac
elif checkSwitchBMCXname "${XNAME}"; then
    readonly SLOT="$(parseSlotXname "${XNAME}")"
    printf "${BOLD}${SLOT}${RESET}\n"
    readonly CABINET="$(parseCabinetXname "${XNAME}")"
    case "${CABINET}" in
        x9|x1)
            bmc="$(parseBMCXname "${XNAME}")"
            bmcUsername=$(scsdBMCUsername "${bmc}")
            bmcPassword=$(scsdBMCPassword "${bmc}")
            printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
            fetchMountainSwitch "${bmc}" "${bmcUsername}" "${bmcPassword}"
            ;;
        x3)
            bmc="$(parseBMCXname "${XNAME}")"
            bmcUsername=$(scsdBMCUsername "${bmc}")
            bmcPassword=$(scsdBMCPassword "${bmc}")
            printf "${BOLD}\t\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
            fetchRiverSwitch "${bmc}" "${bmcUsername}" "${bmcPassword}"
            ;;
        *)
            die "Unkown cabinet ${CABINET}"
            ;;
    esac
elif checkChassisBMCXname "${XNAME}"; then
    printf "${BOLD}${XNAME}${RESET}\n"
    bmcUsername=$(scsdBMCUsername "${XNAME}")
    bmcPassword=$(scsdBMCPassword "${XNAME}")
    printf "${BOLD}\t%-13s %-18s %-18s %-35s %-11s %s\n${RESET}" \
                    "Part" "SerialNumber" "PartNumber" "Model" "Health" "Firmware"
    fetchCMM "${XNAME}" "${bmcUsername}" "${bmcPassword}"
    printf "${BOLD}\t%-13s %-18s %-11s %-7s\n${RESET}" \
                    "Part" "SerialNumber" "Health" "Version"
    fetchCMMPowerSupplyRectifier "${XNAME}" "${bmcUsername}" "${bmcPassword}" 0
    fetchCMMPowerSupplyRectifier "${XNAME}" "${bmcUsername}" "${bmcPassword}" 1
    fetchCMMPowerSupplyRectifier "${XNAME}" "${bmcUsername}" "${bmcPassword}" 2
    fetchCMMPowerSupplyRectifier "${XNAME}" "${bmcUsername}" "${bmcPassword}" 3
else
    die "Unexpected xname ${XNAME}"
fi

exit 0
################################
