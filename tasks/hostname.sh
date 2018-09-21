#!/bin/bash

hostname=$(/usr/bin/hostnamectl --transient)

# Output a JSON result for ease of Task usage in Puppet Task Plans
echo '{ "hostname": "'$hostname'" }'
