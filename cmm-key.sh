cmm-key ()
{
    [[ "$1" == "" ]] && {
        echo "Need xname: e.g 'cmm-key x1000c7'" 1>&2;
        return 1
    };
    eval $(cray scsd bmc creds list --format json --targets $1 | jq -r '.Targets[] | "BMC_USER=" + .Username,"BMC_PASSWD="+.Password');
    [ ! -f ~/.ssh/id_rsa.pub ] && {
        echo "Need ~/.ssh/id_rsa.pub file" 1>&2;
        return 1
    };
    KEY=$(cat ~/.ssh/id_rsa.pub |grep ^ssh-rsa |cut -f2 -d" ");
    curl -vfsk -u ${BMC_USER:-root}:${BMC_PASSWD:-initial0} https://$1/redfish/v1/Managers/BMC/NetworkProtocol -H 'Content-Type: application/json' -XPATCH -d '{"Oem":{"SSHAdmin":{"AuthorizedKeys":"ssh-rsa '$KEY'"}}}'
}

