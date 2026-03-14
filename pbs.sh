pbs() {
    local nodes="${*}"
    readonly nodes

    if [[ -z "${nodes}" ]]; then
        ssh -q "$(loginNode "${CLUSTER_NAME}")" pbsnodes -F json -a \
            | jq -r '.nodes | to_entries[] | "\(.value.resources_available.crayhost)|\(.value.resources_available.host)|\(.value.resources_available.xname)|\(.value.resources_available.switch)|\(.value.resources_available.coretype)|\(.value.resources_available.worktype)|\(.value.state)|\(.value.comment)|\(.value.jobs)"' \
            | awk -F'|' '{ printf "%-3s\t%-8s\t%13-s\t%9-s\t%5-s\t%31-s\t%28-s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' \
            | sort
    else
        ssh -q "$(loginNode "${CLUSTER_NAME}")" pbsnodes -F json "$(nodeset -e "${nodes}")" \
            | jq -r '.nodes | to_entries[] | "\(.value.resources_available.crayhost)|\(.value.resources_available.host)|\(.value.resources_available.xname)|\(.value.resources_available.switch)|\(.value.resources_available.coretype)|\(.value.resources_available.worktype)|\(.value.state)|\(.value.comment)|\(.value.jobs)"' \
            | awk -F'|' '{ printf "%-3s\t%-8s\t%13-s\t%9-s\t%5-s\t%31-s\t%28-s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' \
            | sort
    fi
}

loginNode() {
    local clusterName="${1}"
    readonly clusterName

    if [[ -n "${clusterName}" ]]; then
        declare -A clusterLogin=(
            ["cluster-a"]="login-c1"
            ["cluster-b"]="login-c1"
            ["cluster-c"]="login-c1"
            ["cluster-d"]="login-c1"
            ["cluster-x"]="login-b1"
            ["cluster-y"]="login-b1"
            ["cluster-z"]="access-gw1"
        )
        readonly clusterLogin

        local node="${clusterLogin[$clusterName]}"
        readonly node
        echo "${node}"
    else
        echo "access-gw1"
    fi
}
