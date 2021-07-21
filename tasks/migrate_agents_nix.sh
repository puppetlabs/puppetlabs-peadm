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

if puppet --version | grep -e ^5; then
    echo 
    echo "Puppet 5.x detected, setting certificate_revocation to leaf to facilitate migration..."
    puppet config set --section main certificate_revocation leaf
fi

echo 
echo "Pointing Puppet Agent to new PE server..."
puppet config delete --section main server
puppet config delete --section agent server
puppet config delete --section main server_list
puppet config delete --section agent server_list
puppet config set --section agent server $PT_target_pe

echo 
echo "Performing initial Puppet Agent run..."
puppet agent --no-daemonize --onetime --no-usecacheonfailure --no-splay  2>&1

echo 
echo "Starting the Puppet Agent service..."
service puppet start