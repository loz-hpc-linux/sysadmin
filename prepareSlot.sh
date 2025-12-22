#!/bin/bash

set -euo pipefail

readonly SCRIPTNAME="$(basename ${0})"
readonly BASEDIR="$(dirname ${0})"

########## Functions ###########
source "${BASEDIR}/functions.sh"

shutdown() {
    echo
    echo "###############################"
    echo "SHUTTING DOWN. DO NOT cancel it"
    echo "###############################"
    clush -bw "${nidsComma}" "mv /etc/security/access.conf.${SCRIPTNAME} /etc/security/access.conf"
    echo "####################################################"
    echo "PLEASE, make sure all nodes have the line -:ALL:ALL"
    echo "####################################################"
    clush -bw "${nidsComma}" "tail -n1 /etc/security/access.conf"
    jobState="$(ssh -q "${LOGIN}" "qstat -x -F json -f '${job}'" | jq -r ".Jobs.\"${fullJob}\".job_state")"
    if [[ "${jobState}" == "R" ]]; then
        echo "Deleting job ${job}"
        ssh ${LOGIN} "sudo -u ${user} qdel ${job}"
        echo "Waiting for job to finish"
        until [[ "${jobState}" == "F" ]]; do
            sleep 30
            jobState="$(ssh -q "${LOGIN}" "qstat -x -F json -f '${job}'" | jq -r ".Jobs.\"${fullJob}\".job_state")"
        done
    fi
    ssh -q ${LOGIN} "rm -f ${home}/${SCRIPTNAME}.${slot}.pbs ${home}/${SCRIPTNAME}.${slot}.pbs.o${job} ${home}/${SCRIPTNAME}.${slot}.pbs.e${job}"
    echo "########################################################"
    echo "PLEASE, remember to scroll up and READ the entire OUTPUT"
    echo "########################################################"
    exit 0
}

runSyscheck() {
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local slotNodesXnames="$(nodeset -e "$(ntox $slot)")"
    local siblings="$(nodeset -e ${slotNodesXnames} -x $(nodeset -f ${XNAMES[@]}))"
    echo "Siblings: ${siblings}"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"

    echo "Running syschecker"
    local user="hpeadmin"
    readonly user
    if [[ "${SYSTEM_NAME}" == "exz" ]]; then
        local home="/home/h05/hpeadmin"
    else
        local home="/home/users/hpeadmin"
    fi
    readonly home
    local sshDir="${home}/.ssh"
    readonly ssh
    pbs "${nids}"
    ${DEBUG} && echo "Running pre-flight checks"
    for nid in ${nids}; do
        [[ "$(ssh -q "${LOGIN}" "pbs_rstat -f" | grep ${nid} 2>/dev/null)" ]] || die "Aborting. Node ${nid} is not reserved"
        [[ "$(ssh -q "${LOGIN}" "pbsnodes -F json ${nid}" | jq -r ".nodes.${nid}.jobs")" == "null" ]] || die "Aborting. Job running on node ${nid}"
    done
    ${DEBUG} && echo "Nodes reserved and no job running"
    ${DEBUG} &&  echo "Preparing for running syschecker"
    reservID="$(reservationID "${slot}")"
    if [[ -z "${reservID}" ]]; then
        die "Reservation not found"
    fi
    # NOTE: do not use double quote in -e with nodeset. it must have spaces to work properly
    nidsComma="$(nodeset -S, -e ${nids})"
    clush -q -bw "${nidsComma}" "test -f /etc/security/access.conf.${SCRIPTNAME} && mv /etc/security/access.conf.${SCRIPTNAME} /etc/security/access.conf || true"
    clush -q -bw "${nidsComma}" "sed -i.${SCRIPTNAME} 's/-:ALL:ALL//g' /etc/security/access.conf"
    trap shutdown ERR INT TERM
    mkdir -p "${sshDir}"
    test -f "${sshDir}/id_rsa" || ssh-keygen -q -N "" -f "${sshDir}/id_rsa"
    clush -qbw "${nidsComma}" mkdir -p "${sshDir}"
    clush -qbw "${nidsComma}" -c "${sshDir}/id_rsa"
    clush -qbw "${nidsComma}" -c "${sshDir}/id_rsa.pub" --dest "${sshDir}/authorized_keys"
    clush -qbw "${nidsComma}" "chown -R ${user}: ${sshDir}"
    ${DEBUG} && echo "Submitting PBS job"
    local n0="$(echo $nids | awk '{ print $1 }')"
    local n1="$(echo $nids | awk '{ print $2 }')"
    local n2="$(echo $nids | awk '{ print $3 }')"
    local n3="$(echo $nids | awk '{ print $4 }')"
    local coreTypeJob="$(ssh -q ${LOGIN} "pbsnodes -F json $n0 | jq -r '.nodes.${n0}.resources_available.coretype'")"
    local memMb="$(ssh -q ${LOGIN} "pbsnodes -F json $n0 | jq -r '.nodes.${n0}.resources_available.mem' | sed -e 's/mb$//g'")"
    local memJob="$(( $memMb - 1024 ))"
    local cpuJob="$(ssh -q ${LOGIN} "pbsnodes -F json $n0 | jq -r '.nodes.${n0}.resources_available.ncpus'")"
    cat << EOF > ${SCRIPTNAME}.${slot}.pbs
#!/bin/bash
#PBS -l select=1:host=${n0}:mem=${memJob}mb:ncpus=${cpuJob}:coretype=${coreTypeJob}+host=${n1}:mem=${memJob}mb:ncpus=${cpuJob}:coretype=${coreTypeJob}+host=${n2}:mem=${memJob}mb:ncpus=${cpuJob}:coretype=${coreTypeJob}+host=${n3}:mem=${memJob}mb:ncpus=${cpuJob}:coretype=${coreTypeJob}
#PBS -q ${reservID}
#PBS -l place=exclhost
#PBS -l walltime=01:15:00
#PBS -j oe
test -f /lustre/ehz?res/systemchecker/SC-v4.6.0-cpu-x86_64.tar.gz && remote_sc=/lustre/ehz?res/systemchecker/SC-v4.6.0-cpu-x86_64.tar.gz
if [[ -z "\${remote_sc}" ]]; then
    echo "Please, copy systemchecker to research file system at /lustre/ehz?res/systemchecker/SC-v4.6.0-cpu-x86_64.tar.gz"
    exit 1
fi
tar xzf \$remote_sc
cd SC-v4.6.0
. load-sc.sh SS
export PBS_O_PATH="\${PBS_O_PATH}:/opt/cray/pals/default/bin"
export SC_SHARED_SC_PKG=\${remote_sc}
test -f ~/.ssh/known_hosts && mv ~/.ssh/known_hosts ~/.ssh/known_hosts.prepareSlot.sh
ssh-keyscan ${nids} >> ~/.ssh/known_hosts
syschecker -w "${nidsComma}" -t install -t pulse
syschecker -w "${nidsComma}" -t linktest -u 90 -p 24
syschecker -w "${nidsComma}" -t cpuperf
syschecker -w "${nidsComma}" -t stream-cpu
MEMORY_PRESSURE=0.8 syschecker -w "${nidsComma}" -t hpl
SC_TASK_GROUP_SIZE=2 syschecker -w "${nidsComma}" -t hpl -r 2
SC_TASK_GROUP_SIZE=2 syschecker -w "${nidsComma}" -t bisection -r 50 -u 90
rm -f ~/.ssh/known_hosts
test -f ~/.ssh/known_hosts.prepareSlot.sh && mv ~/.ssh/known_hosts.prepareSlot.sh ~/.ssh/known_hosts
EOF
    scp -q ${SCRIPTNAME}.${slot}.pbs ${LOGIN}:${home}/
    rm ${SCRIPTNAME}.${slot}.pbs
    local fullJob="$(ssh -q ${LOGIN} "cd ${home} && sudo -u ${user} qsub ${SCRIPTNAME}.${slot}.pbs")"
    local job="$(echo "${fullJob}" | cut -d'.' -f1)"
    if [[ ! -n "${job}" ]]; then
        die "Job submission failed"
    fi
    echo "Job: ${fullJob}"
    echo "Waiting for it to be running"
    jobState="$(ssh -q "${LOGIN}" "qstat -x -F json -f '${job}'" | jq -r ".Jobs.\"${fullJob}\".job_state")"
    until [[ "${jobState}" == "R" ]]; do
        ${DEBUG} && echo "Job state: ${jobState}. Sleeping 10s"
        sleep 10
        jobState="$(ssh -q "${LOGIN}" "qstat -x -F json -f '${job}'" | jq -r ".Jobs.\"${fullJob}\".job_state")"
    done
    echo "Waiting for it to finish. It may take a while"
    jobState="$(ssh -q "${LOGIN}" "qstat -x -F json -f '${job}'" | jq -r ".Jobs.\"${fullJob}\".job_state")"
    until [[ "${jobState}" == "F" ]]; do
        ${DEBUG} && echo "Job state: ${jobState}. Sleeping 30s"
        sleep 30
        jobState="$(ssh -q "${LOGIN}" "qstat -x -F json -f '${job}'" | jq -r ".Jobs.\"${fullJob}\".job_state")"
    done
    echo "Reading job's stdout and stderr"
    ssh -q ${LOGIN} "cat ${home}/${SCRIPTNAME}.${slot}.pbs.o${job}"
    ssh -q ${LOGIN} "rm -f ${home}/${SCRIPTNAME}.${slot}.pbs ${home}/${SCRIPTNAME}.${slot}.pbs.o${job} ${home}/${SCRIPTNAME}.${slot}.pbs.e${job}"
    shutdown
}

commentReserveNode() {
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local slotNodesXnames="$(nodeset -e "$(ntox $slot)")"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"
    local nodes="$(nodeset -e "$(xton ${XNAMES[@]})")"
    reservID="$(reservationID "${XNAMES[0]}")"
    if [[ -n "${reservID}" ]]; then
        echo "Reservation found: ${reservID}. Skipping"
        return 0
    fi
    echo "Comment and reserve"
    echo "Reserving nodes ${nodes}"
    echo "Previous status"
    pbs "${nids}"
    for x in ${XNAMES[@]}; do
        n="$(xton "${x}")"
        pbsComment "${TICKET}" "${n}"
    done
    reservationSubmit "${XNAMES[0]}" "${START}" "${END}" "${nodes}"
    echo "Sleeping for reservation to take place"
    sleep 4
    echo "Current status"
    pbs "${nids}"
}

commentReserveSlot() {
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local slotNodesXnames="$(nodeset -e "$(ntox $slot)")"
    local siblings="$(nodeset -e ${slotNodesXnames} -x $(nodeset -f ${XNAMES[@]}))"
    echo "Siblings: ${siblings}"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"
    reservID="$(reservationID "${slot}")"
    if [[ -n "${reservID}" ]]; then
        echo "Reservation found: ${reservID}. Skipping"
        return 0
    fi
    echo "Comment and reserve"
    echo "Reserving nodes ${nids}"
    echo "Previous status"
    pbs "${nids}"
    for x in ${XNAMES[@]}; do
        n="$(xton "${x}")"
        pbsComment "${TICKET}" "${n}"
    done
    for x in ${siblings}; do
        n="$(xton "${x}")"
        pbsComment "SIBLING ${TICKET}" "${n}"
    done
    echo "Deleting node ${XNAMES[0]} reservation"
    nodeReservID="$(reservationID "${XNAMES[0]}")"
    if [[ -z "${nodeReservID}" ]]; then
        ${DEBUG} && echoStderr "Node reservation not found"
    else
        reservationDel "${nodeReservID}"
    fi
    reservationSubmit "${slot}" "${START}" "${END}" "${nids}"
    echo "Sleeping for reservation to take place"
    sleep 4

    echo "Current status"
    pbs "${nids}"
}

unreserve(){
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"
    while true; do
        echo "###################################"
        echo "This action is not going to run NHC"
        echo "neither clear PBS comments"
        echo "###################################"
        echo "Do you want to proceed? (yes/no)"
        read -r user_input
        case "$user_input" in
            yes)
                echo "With great power comes great responsibility!"
                break
                ;;
            no)
                die "See you!"
                ;;
            *)
                echo "Invalid input. Please type 'yes' or 'no'."
                ;;
        esac
    done
    echo "Previous status"
    pbs "${nids}"
    reservID="$(reservationID "${slot}")"
    if [[ -z "${reservID}" ]]; then
        die "Reservation not found"
    fi
    echo "Removing reservation"
    reservationDel "${reservID}"
    echo "Sleeping for reservation to go away"
    sleep 4
    echo "Current status"
    pbs "${nids}"
}

bringSlotDown() {
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local slotNodesXnames="$(nodeset -e "$(ntox $slot)")"
    local siblings="$(nodeset -e ${slotNodesXnames} -x $(nodeset -f ${XNAMES[@]}))"
    echo "Siblings: ${siblings}"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"

    echo "Bring nodes and slot down"
    echo "Checking if nodes are reserved"
    for n in ${nids}; do
        [[ "$(ssh -q -o ConnectTimeout=10 "${LOGIN}" "pbs_rstat -f" | grep ${n} 2>/dev/null)" ]] || die "Aborting. Node ${n} is not reserved"
    done
    echo "Checking if nodes are not running any job"
    for n in ${nids}; do
        [[ "$(ssh -q -o ConnectTimeout=10 "${LOGIN}" "pbsnodes -F json ${n}" | jq -r ".nodes.${n}.jobs")" == "null" ]] || die "Aborting. Job running on node ${n}"
    done
    echo "Checking nodes are not special role"
    askConfirm=false
    for n in ${nids}; do
        role="$(ssh -q -o ConnectTimeout=10 "${LOGIN}" "pbsnodes -F json ${n}" | jq -r ".nodes.${n}.resources_available.worktype")"
        if [[ "${role}" != "compute" ]]; then
            askConfirm=true
            echo "#### ATTENTION: node ${n} ${role}"
        fi
    done
    if ${askConfirm}; then
        while true; do
            echo "Do you want to proceed? (yes/no)"
            read -r user_input
            case "$user_input" in
                yes)
                    echo "With great power comes great responsibility!"
                    break
                    ;;
                no)
                    die "See you!"
                    ;;
                *)
                    echo "Invalid input. Please type 'yes' or 'no'."
                    ;;
            esac
        done
    fi
    # NOTE: do not use double quote in -e with nodeset. it must have spaces to work properly
    xnamesComma="$(nodeset -S, -e ${slotNodesXnames})"
    echo "Powering nodes down"
    output="$(cray capmc xname_off create --xnames "${xnamesComma}" --format json)"
    exitCode="$(echo "${output}" | jq -r '.e')"
    errMsg="$(echo "${output}" | jq -r '.err_msg')"
    [[ "${exitCode}" == "0" ]] || die "CAPMC xname_off Error: ${errMsg}"
    [[ "${errMsg}" == "" ]] || die "CAPMC xname_off Error: ${errMsg}"
    unset output
    unset exitCode
    unset errMsg
    count=0
    retry=20
    wait=30
    force=false
    echo "Please, wait up to 10 minutes for node to shutdown gracefully!"
    date
    until [[ "$(cray capmc get_xname_status create --xnames "${xnamesComma}" --format json | jq -r .on)" = "null" ]]; do
        count=$((count+1))
        if [[ ${count} -gt ${retry} ]]; then
            force=true
            break
        fi
        echo "Nodes are still up. Sleeping ${wait} seconds"
        sleep ${wait}
    done
    unset count
    unset retry
    unset wait
    if $force; then
        echo "Running forced power off"
        output="$(cray capmc xname_off create --xnames "${xnamesComma}" --force true --format json)"
        exitCode="$(echo "$output" | jq -r '.e')"
        errMsg="$(echo "$output" | jq -r '.err_msg')"
        [[ "${exitCode}" == "0" ]] || die "CAPMC xname_off Error: $errMsg"
        [[ "${errMsg}" == "" ]] || die "CAPMC xname_off Error: $errMsg"
        unset output
        unset exitCode
        unset errMsg
        count=0
        retry=6
        wait=30
        force=false
        until [[ "$(cray capmc get_xname_status create --xnames "${xnamesComma}" --format json | jq -r .on)" = "null" ]]; do
            count=$((count+1))
            if [[ ${count} -gt ${retry} ]]; then
                die "Cannot stop nodes"
            fi
            echo "Nodes are still up. Sleeping ${wait} seconds"
            sleep ${wait}
        done
        unset count
        unset retry
        unset wait
    fi
    cray capmc get_xname_status create --xnames "${xnamesComma}"
    echo "Disabling slot in HSM"
    cray hsm state components enabled update --enabled false "${slot}"
    echo "Powering blade off"
    cray power transition off --xnames "${slot}"
    count=0
    retry=4
    wait=30
    until [[ "$(cray power status list --xnames $slot --format json | jq -r .status[].powerState)" = "off" ]]; do
        count=$((count+1))
        if [[ ${count} -gt ${retry} ]]; then
            echo "Cannot stop slot ${slot}"
            return 1
        fi
        echo "Slot is still up"
        sleep ${wait}
    done
    unset count
    unset retry
    unset wait
        echo
        echo "Slot should now be down... Checking chassis status..."
        echo
        ssh -q -o ConnectTimeout=10 "$(echo "${slot}" | sed -E 's/^(x[0-9]+c[0-9]+)s[0-9]+$/\1b0/')" 'redfish chassis status' || echo "WARN: chassis status query failed"
    echo Done
}

bringSlotUp() {
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local slotNodesXnames="$(nodeset -e "$(ntox $slot)")"
    local siblings="$(nodeset -e ${slotNodesXnames} -x $(nodeset -f ${XNAMES[@]}))"
    echo "Siblings: ${siblings}"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"

    echo "Bring nodes and slot up"
    echo "Powering blade on"
    cray power transition on --xnames "${slot}"
    count=0
    retry=4
    wait=30
    until [[ "$(cray power status list --xnames "${slot}" --format json | jq -r .status[].powerState)" = "on" ]]; do
        count=$((count+1))
        if [[ ${count} -gt ${retry} ]]; then
            echo "Cannot start slot ${slot}"
            return 1
        fi
        echo "Slot is still down"
        sleep ${wait}
    done
    unset count
    unset retry
    unset wait
    echo "Waiting for Redfish"
    until $(ssh -q -o ConnectTimeout=10 ${slot}b0 'redfish node status' | grep -e Off -e On >/dev/null 2>&1); do
        echo "Redfish on ${slot}b0 not up. Waiting 30s"
        sleep 30
    done
    # NOTE: do not use double quote in -e with nodeset. it must have spaces to work properly
    xnamesComma="$(nodeset -S, -e ${slotNodesXnames})"
    echo "Powering nodes on"
    cray capmc xname_on create --xnames "${xnamesComma}"
    count=0
    retry=5
    wait=30
    until [[ "$(cray capmc get_xname_status create --xnames "${xnamesComma}" --format json | jq -r .off)" = "null" ]]; do
        count=$((count+1))
        if [[ ${count} -gt ${retry} ]]; then
            die "Cannot start nodes"
        fi
        echo "nodes are still down. Sleeping ${wait} seconds"
        sleep ${wait}
    done
    unset count
    unset retry
    unset wait
    echo "Waiting for SSH"
    count=0
    retry=15
    wait=60
    for n in ${nids}; do
        until $(echo quit | nc -w 5 -N ${n}-nmn 22 >/dev/null 2>&1); do
            count=$((count+1))
            if [[ ${count} -gt ${retry} ]]; then
                die "${n} Timed out waiting for SSH"
            fi
            echo "${n} is still booting. Sleeping ${wait} seconds"
            sleep ${wait}
        done
        echo "${n} ssh available"
    done
    unset count
    unset retry
    unset wait
    echo "Waiting for CFS"
    last_job=$(cray cfs components describe ${XNAMES[0]} --format json | jq -r .state[0].lastUpdated | xargs date +%s --date 2>/dev/null || date +%s)
    now=$(date +%s)
    while [ $((now-last_job)) -gt 300 ]; do
        sleep 60
        last_job=$(cray cfs components describe ${XNAMES[0]} --format json | jq -r .state[0].lastUpdated | xargs date +%s --date 2>/dev/null || date +%s)
        now=$(date +%s)
    done
    until $(cray cfs components describe ${XNAMES[0]} --format json | jq ".configurationStatus" | grep -w configured >/dev/null 2>&1); do
        sleep 60
    done
    echo "Collecting serial numbers"
    for x in ${XNAMES[@]}; do
        serialNumber.sh "${x}"
    done
    echo "Done"

}

sameSlot() {
    local xname="${1}"
    readonly xname
    shift
    local xnames="${*}"
    readonly xnames
    local slot="$(parseSlotXname "${xname}")"
    for x in ${xnames}; do
        s="$(parseSlotXname "${x}")"
        test $slot != $s && return 1
    done
    return 0
}

clean() {
    echo "Xnames: ${XNAMES[@]}"
    local slot="$(parseSlotXname "${XNAMES[0]}")"
    local slotNodesXnames="$(nodeset -e "$(ntox $slot)")"
    local siblings="$(nodeset -e ${slotNodesXnames} -x $(nodeset -f ${XNAMES[@]}))"
    echo "Siblings: ${siblings}"
    local nids="$(nodeset -e "$(xton $slot)")"
    echo "NIDs: ${nids}"
    echo "Running NHC"
    for n in ${nids}; do
        ssh -q -o ConnectTimeout=10 ${n} "/opt/nhc/sbin/nhc -D /opt/nhc/etc/nhc -c /var/spool/pbs/mom_priv/hooks/nhc.CF -v -l - -n extras -t 60 DF_FLAGS=-Tkal 2>&1"
    done
    echo "Sleeping 10s for pbs to get updated"
    sleep 10
    for n in ${nids}; do
        [[ "$(ssh -q -o ConnectTimeout=10 "${LOGIN}" "pbsnodes -F json ${n}" | jq -r ".nodes.${n}.state")" =~ offline ]] && die "Aborting. Node ${n} is offline in PBS"
        [[ "$(ssh -q -o ConnectTimeout=10 "${LOGIN}" "pbsnodes -F json ${n}" | jq -r ".nodes.${n}.state")" =~ down ]] && die "Aborting. Node ${n} is down in PBS"
    done
    echo "Onlining nodes ${nids}"
    echo "Previous status"
    pbs "${nids}"
    slotReservID="$(reservationID "${slot}")"
    if [[ -z "${slotReservID}" ]]; then
        echoStderr "Slot reservation not found"
    else
        reservationDel "${slotReservID}"
    fi
    pbsComment "" "${nids}"
    pbsOnline "${nids}"
    echo "Current status"
    pbs "${nids}"
    echo "Enabling slot in HSM"
    cray hsm state components enabled update --enabled true ${slot}
    count=0
    retry=3
    wait=10
    until [[ "$(cray hsm state components describe ${slot} --format json | jq -r ".Enabled")" = "true" ]]; do
        count=$((count+1))
        if [[ ${count} -gt ${retry} ]]; then
            die "Cannot enable slot ${slot} in HSM"
        fi
        echo "slot is still disabled. Sleeping ${wait} seconds"
        sleep ${wait}
    done
    unset count
    unset retry
    unset wait
}

usage() {
    die """Usage: $0 [-d] [-h] -e [END_TIME] -s [START_TIME] -a ACTION -t [TICKET] -x NODE_XNAME [-l LOGIN_NODE]

Parameters:
-a => Action. Valid values are: syscheck, down, reserveNode, reserveSlot, unreserve, clean, and up
-x => Node ID following XNAME convention. Eg.: x9000c1s1b0n0

Options:
-d => Display debug messages in STDOUT
-e => Reservation end time. Defaults to +56 days
-h => Display this help
-s => Reservation start time. Defaults +4 sec
-t => Ticket ID where work is being tracked. Eg.: UKMET-1234 / SFDC 123456789
-l => Specify non default login node (in event default fails) Eg.: login03"""
}

################################

#### Main script execution #####

ACTION=""
DEBUG="false"
END="+ 56 days"
START="+4 sec"
TICKET=""
XNAMES=()
LOGIN=""
while getopts "a:de:hs:l:t:x:" option; do
    case ${option} in
        a)
            ACTION="${OPTARG}"
            ;;
        d)
            DEBUG=true
            ;;
        e)
            END="${OPTARG}"
            ;;
        h)
            usage
            ;;
        s)
            START="${OPTARG}"
            ;;
        t)
            TICKET="${OPTARG}"
            ;;
        x)
            XNAMES+=("$OPTARG")
            ;;

        l)
            LOGIN="${OPTARG}"
            ;;
        *)
            echoStderr "Invalid option: -${option}"
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

test -n "${ACTION}" || usage
test -v XNAMES || usage
test -n "${SYSTEM_NAME}" || echoStderr "WARNING: Env var SYSTEM_NAME not set. Assuming default config"

for XNAME in ${XNAMES[@]}; do
    checkNodeXname "${XNAME}" || die "Invalid node XNAME ${XNAME}"
done
if ! sameSlot ${XNAMES[@]}; then
    die "${XNAMES[@]}: Xnames must belong to the same slot"
fi

LOGIN="${LOGIN:-$(loginNode "${SYSTEM_NAME}")}"
readonly LOGIN

# Check if SSH is reachable
if ! timeout 5 ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$LOGIN" true; then
    echoStderr "ERROR: Cannot SSH into $LOGIN. Login node is unreachable."
    exit 1
fi

# Check if PBS works via SSH
if ! ssh -q "$LOGIN" "pbsnodes -a" &>/dev/null; then
    echoStderr "ERROR: SSH to $LOGIN succeeded but PBS command failed. PBS may be down or misconfigured on $LOGIN."
    exit 1
fi

date
case "${ACTION}" in
    down)
        bringSlotDown
        ;;
    reserveNode)
        test -n "${TICKET}" || die "Please, pass argument -t with ticket identification"
        echo "${TICKET}" | grep -q '[^a-zA-Z0-9 -_]' && die "Ticket cannot have special chars"
        commentReserveNode
        ;;
    reserveSlot)
        test -n "${TICKET}" || die "Please, pass argument -t with ticket identification"
        echo "${TICKET}" | grep -q '[^a-zA-Z0-9 -_]' && die "Ticket cannot have special chars"
        commentReserveSlot
        ;;
    clean)
        clean
        ;;
    unreserve)
        unreserve
        ;;
    up)
        bringSlotUp
        ;;
    syscheck)
        runSyscheck
        ;;
    *)
        die "Invalid action ${ACTION}. See help"
        ;;
esac
date
exit 0
