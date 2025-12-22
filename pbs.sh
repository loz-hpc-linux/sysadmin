pbs() {
    local nodes="${*}"
    readonly nodes
    if [[ -z "${nodes}" ]]; then
        ssh -q "$(loginNode "${SYSTEM_NAME}")" pbsnodes -F json -a | jq -r '.nodes | to_entries[] | "\(.value.resources_available.crayhost)|\(.value.resources_available.host)|\(.value.resources_available.xname)|\(.value.resources_available.switch)|\(.value.resources_available.coretype)|\(.value.resources_available.worktype)|\(.value.state)|\(.value.comment)|\(.value.jobs)"' | awk -F'|' '{ printf "%-3s\t%-8s\t%13-s\t%9-s\t%5-s\t%31-s\t%28-s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' | sort
    else
        ssh -q "$(loginNode "${SYSTEM_NAME}")" pbsnodes -F json $(nodeset -e ${nodes}) | jq -r '.nodes | to_entries[] | "\(.value.resources_available.crayhost)|\(.value.resources_available.host)|\(.value.resources_available.xname)|\(.value.resources_available.switch)|\(.value.resources_available.coretype)|\(.value.resources_available.worktype)|\(.value.state)|\(.value.comment)|\(.value.jobs)"' | awk -F'|' '{ printf "%-3s\t%-8s\t%13-s\t%9-s\t%5-s\t%31-s\t%28-s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' | sort
    fi
}

loginNode() {
    local systemName="${1}"
    readonly systemName
    if [[ -n "${systemName}" ]]; then
        declare -A systemLogin=( ["exa"]="login05" ["exb"]="login05" ["exc"]="login05" ["exd"]="login05" ["exx"]="login03" ["exy"]="login03" ["exz"]="uan01" )
        readonly systemLogin
        local node="${systemLogin[$systemName]}"
        readonly node
        echo "${node}"
    else
        echo "uan01"
    fi
}
