#!/bin/bash

hostname=$(/usr/bin/hostname -f)

# Output a JSON result for ease of Task usage in Puppet Task Plans
echo '{ "hostname": "'$hostname'" }'
