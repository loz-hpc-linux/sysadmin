#!/bin/bash

readonly BOLD=$(tput bold)
readonly RESET=$(tput sgr0)

readonly NODE_MAP_FILE="${NODE_MAP_FILE:-/etc/hpc/node-map}"

checkNodeBMCXname() {
    local xname="${1}"
    readonly xname
    local validation="$(echo ${xname} | sed -n 's/^\(x[1,3,9][0-9]*c[0-9]*s[0-9]*b[0,1]\)$/\1/p')"
    readonly validation
    test -n "${validation}" || return 1
    return 0
}

checkNodeSlotXname() {
    local xname="${1}"
    readonly xname
    local validation="$(echo ${xname} | sed -n 's/^\(x[1,3,9][0-9]*c[0-9]*s[0-9]\)$/\1/p')"
    readonly validation
    test -n "${validation}" || return 1
    return 0
}

checkNodeXname() {
    local xname="${1}"
    readonly xname
    local validation="$(echo ${xname} | sed -n 's/^\(x[1,3,9][0-9]*c[0-9]*s[0-9]*b[0,1]n[0-3]\)$/\1/p')"
    readonly validation
    test -n "${validation}" || return 1
    return 0
}

checkSwitchBMCXname() {
    local xname="${1}"
    readonly xname
    local validation="$(echo ${xname} | sed -n 's/^\(x[1,3,9][0-9]*c[0-9]*r[0-9]b0\)$/\1/p')"
    readonly validation
    test -n "${validation}" || return 1
    return 0
}

checkChassisBMCXname() {
    local xname="${1}"
    readonly xname
    local validation="$(echo ${xname} | sed -n 's/^\(x[1,3,9][0-9]*c[0-9]*b0\)$/\1/p')"
    readonly validation
    test -n "${validation}" || return 1
    return 0
}

die() {
    local msg="${*}"
    readonly msg
    echoStderr "${msg}"
    exit 1
}

checkIfDebug() {
    local msg="${*}"
    readonly msg
    test $DEBUG = false \
    || echo -e "${msg}"
}

echoIfVerbose() {
    local msg="${*}"
    readonly msg
    test $verbose = false \
    || echo -e "${msg}"
}

echoStderr() {
    local msg="${*}"
    readonly msg
    >&2 echo -e "${msg}"
}

isGenoa() {
    local nid="${1}"
    readonly nid
    [[ "$(ssh -q "$(loginNode "${SYSTEM_NAME}")" pbsnodes -F json ${nid} | jq -r ".nodes.${nid}.resources_available.coretype")" = "genoa" ]]
    return $?
}

isMilan() {
    local nid="${1}"
    readonly nid
    [[ "$(ssh -q "$(loginNode "${SYSTEM_NAME}")" pbsnodes -F json ${nid} | jq -r ".nodes.${nid}.resources_available.coretype")" = "milan" ]]
    return $?
}

# Global cache variable
__CACHED_LOGIN_NODE=""

loginNode() {
    local systemName="${1}"
    readonly systemName

    # Return cached value if set
    if [[ -n "${__CACHED_LOGIN_NODE}" ]]; then
        echo "${__CACHED_LOGIN_NODE}"
        return 0
    fi

    # List of fallback login nodes
    local login_candidates=("login-a1" "login-a2" "login-b1" "login-b2" "login-c1")

    # Prioritize based on system name
    if [[ "${systemName}" == "cluster-b" ]]; then
        login_candidates=("login-b1" "login-b2" "login-a2" "login-a1" "login-c1")
    elif [[ "${systemName}" == "cluster-a" ]]; then
        login_candidates=("login-c1" "login-b2" "login-b1" "login-a2" "login-a1")
    elif [[ "${systemName}" == "cluster-c" ]]; then
        __CACHED_LOGIN_NODE="access-gw1"
        echo "access-gw1"
        return 0
    fi

    for login in "${login_candidates[@]}"; do
        if timeout 5 ssh -q -o BatchMode=yes -o ConnectTimeout=3 "$login" true; then
            if ssh -q "$login" "pbsnodes -a" >/dev/null 2>&1; then
                __CACHED_LOGIN_NODE="$login"
                echo "$login"
                return 0
            fi
        fi
    done

    echo "ERROR: No working login node found for system ${systemName}" >&2
    return 1
}

pbsUser() {
    local systemName="${1}"
    readonly systemName
    if [[ -n "${systemName}" ]]; then
        echo "clusteradmin"
    else
        echo "root"
    fi
}

ntox() {
    local nodes="${*}"
    readonly nodes
    for n in $(nodeset -e ${nodes});
    do
        grep $n "${NODE_MAP_FILE}" | cut -f1 -d' ';
    done | nodeset -f
}

parseBMCXname() {
    local xname="${1}"
    readonly xname
    echo ${xname} | sed -n 's/\(x[0-9][0-9]*c[0-9]*[sr][0-9]*b[0,1]\)\(.*\)*/\1/p'
}

parseCabinetXname() {
    local xname="${1}"
    readonly xname
    echo ${xname} | sed -n 's/\(x[0-9]\)\(.*\)*/\1/p'
}

parseNodeNumber() {
    local xname="${1}"
    readonly xname
    echo ${xname} | sed -n 's/x[0-9][0-9]*c[0-9]*[sr][0-9]*b[0,1]n\([0-3]\)$/\1/p'
}

parseSlotXname() {
    local xname="${1}"
    readonly xname
    echo ${xname} | sed -n 's/\(x[0-9][0-9]*c[0-9]*[sr][0-9]*\)\(.*\)*/\1/p'
}

pbs() {
    local nodes="${*}"
    readonly nodes
    ssh -q "$(loginNode "${SYSTEM_NAME}")" pbsnodes -F json $(nodeset -e ${nodes}) | jq -r '.nodes | to_entries[] | "\(.value.resources_available.crayhost)|\(.value.resources_available.host)|\(.value.resources_available.xname)|\(.value.resources_available.switch)|\(.value.resources_available.coretype)|\(.value.resources_available.worktype)|\(.value.state)|\(.value.comment)|\(.value.jobs)"' | awk -F'|' '{ printf "%-3s\t%-8s\t%13-s\t%9-s\t%5-s\t%31-s\t%28-s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }'
}

pbsComment() {
    local comment="${1}"
    readonly comment
    shift
    local nodes="${*}"
    readonly nodes
    ssh -q "$(loginNode "${SYSTEM_NAME}")" "sudo -u '$(pbsUser "${SYSTEM_NAME}")' pbsnodes -C '${comment}' ${nodes}"
}

pbsOffline() {
    local nodes="${*}"
    readonly nodes
    ssh -q "$(loginNode "${SYSTEM_NAME}")" "sudo -u '$(pbsUser "${SYSTEM_NAME}")' pbsnodes -o ${nodes}"
}

pbsOnline() {
    local nodes="${*}"
    readonly nodes
    ssh -q "$(loginNode "${SYSTEM_NAME}")" "sudo -u '$(pbsUser "${SYSTEM_NAME}")' pbsnodes -r ${nodes}"
}

redfishCorrectCredentials() {
    local bmc="${1}"
    readonly bmc
    local bmcUsername="${2}"
    readonly bmcUsername
    local bmcPassword="${3}"
    readonly bmcPassword
    curl --fail --insecure --silent --header 'Accept:application/json' --user "${bmcUsername}:${bmcPassword}" "https://${bmc}/redfish/v1/SessionService/Sessions" 2>&1
    return $?
}

redfishGET() {
    local bmc="${1}"
    readonly bmc
    local bmcUsername="${2}"
    readonly bmcUsername
    local bmcPassword="${3}"
    readonly bmcPassword
    local uri="${4}"
    readonly uri
    curl --fail --insecure --silent --header 'Accept:application/json' --user "${bmcUsername}:${bmcPassword}" "https://${bmc}/redfish/v1/${uri}" 2>&1
}

reservationDel() {
    local reservationID="${1}"
    readonly reservationID
    ssh -q "$(loginNode "${SYSTEM_NAME}")" "sudo -u '$(pbsUser "${SYSTEM_NAME}")' pbs_rdel '${reservationID}'"
}

reservationID() {
    local reservationName="${1}"
    readonly reservationName
    ssh -q "$(loginNode "${SYSTEM_NAME}")" pbs_rstat -f | grep -B 1 "Reserve_Name = ${reservationName}$" | head -n 1 | cut -d':' -f2 | cut -d'.' -f1 || true
}

reservationSubmit() {
    local reservationName="${1}"
    readonly reservationName
    local start="${2}"
    readonly start
    local end="${3}"
    readonly end
    shift 3
    local nodes="${*}"
    readonly nodes
    ssh -q "$(loginNode "${SYSTEM_NAME}")" "sudo -u '$(pbsUser "${SYSTEM_NAME}")' pbs_rsub -U '$(pbsUser "${SYSTEM_NAME}")@*' -N '${reservationName}' -R $(date +%Y%m%d%H%M.%S -d "${start}") -E $(date +%Y%m%d%H%M.%S -d "${end}") --hosts ${nodes}"
}

scsdBMCPassword() {
    local bmc="${1}"
    readonly bmc
    local pass=$(cray scsd bmc creds list --format json --targets "${bmc}" | jq -r .Targets[].Password 2>/dev/null)
    readonly pass
    echo $pass
}

scsdBMCUsername() {
    local bmc="${1}"
    readonly bmc
    local user=$(cray scsd bmc creds list --format json --targets "${bmc}" | jq -r .Targets[].Username 2>/dev/null)
    readonly user
    echo $user
}

siblings() {
    local xname="${1}"
    readonly xname
    local nid="${2}"
    readonly nid
    local slot="$(parseSlotXname "${xname}")"
    readonly slot
    local slot_nids=$(xton "${slot}" | nodeset -e)
    readonly slot_nids
    local slot_nid
    for slot_nid in ${slot_nids}; do
        if [[ "${slot_nid}" == "${nid}" ]]; then
            continue
        fi
        echo -n "$slot_nid "
    done
}

slotBMC() {
    local slot_xname="${1}"
    readonly slot_xname
    echo "$(nodeset -S'\n' -e $(ntox "${slot_xname}") | sed -e 's/n0//g' -e 's/n1//g' -e 's/n2//g' -e 's/n3//g' | sort -u)"
}

xton() {
    local nodes="${*}"
    readonly nodes
    for n in $(nodeset -e ${nodes});
    do
        grep $n "${NODE_MAP_FILE}" | cut -f2 -d' ';
    done | nodeset -f
}
