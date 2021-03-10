#!/bin/bash

# Ensure we can reach the target Puppet Enterprise server
echo "Verifying connectivity to target Puppet server $PT_target_pe:8140..."
if timeout 1 bash -c "cat < /dev/null > /dev/tcp/$PT_target_pe/8140"; then
    echo "Target Puppet server is reacheable"
else
    echo "Target Puppet server is not reacheable, aborting migration!"
    exit 1
fi

# Ensure Curl is installed
if ! command -v curl &> /dev/null; then
    echo "Curl is not installed on this system, unable to continue!"
    exit 2
fi

echo 
echo "Stopping the Puppet Agent service..."
service puppet stop 2>&1

if [ $PT_regenerate == 'true' ]; then
    echo 
    echo "Regenerate flag detected, clearing out existing node certificates before migration..."
    localcacert=$(puppet config print localcacert)
    hostcert=$(puppet config print hostcert)
    hostprivkey=$(puppet config print hostprivkey)
    hostpubkey=$(puppet config print hostpubkey)
    hostcrl=$(puppet config print hostcrl)
    hostcsr=$(puppet config print hostcsr)
    declare -a arr=("$localcacert" "$hostcert" "$hostprivkey" "$hostpubkey" "$hostcrl" "$hostcsr")
    for i in "${arr[@]}"
    do
        if [ -f "$i" ]; then
            echo "Deleting $i..."
            rm -f $i 2>&1
        fi
    done
    echo "Existing node certificates have been cleared, new certificates will be generated on the next Puppet run"
fi

echo 
echo "Pointing Puppet Agent to new PE server..."
puppet config set server $PT_target_pe

echo 
echo "Installing the new Puppet Agent..."
curl -k https://$PT_target_pe:8140/packages/current/install.bash | sudo bash 2>&1

if [ $? -gt 0 ]; then
    echo "Installation of new Puppet Agent failed! Check the error for details."
    exit 3
fi

echo 
echo "Performing initial Puppet Agent run..."
puppet agent -t 2>&1

echo 
echo "Starting the Puppet Agent service..."
service puppet start