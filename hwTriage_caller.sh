#!/bin/bash

# Adding date to time stamp command
echo "Time issued"
date
echo ""

#echo "Input node xname to test eg: x1002c4s5b0n0:"
echo "Input node xname to test eg: x####c#s#b#n#:"
# Read input from stdin
read -r input

BMC=$(echo $input|sed 's/n.$//')
eval $(cray scsd bmc creds list --format json --targets $BMC | jq -r '.Targets[] | "BMC_USER=" + .Username,"BMC_PASSWD="+.Password')

cd /opt/clmgr/hardware-triage-tool/
command='/opt/clmgr/hardware-triage-tool/hwtriage -u $BMC_USER -p $BMC_PASSWD -n $input'

echo " Running - $command "
eval "$command"
