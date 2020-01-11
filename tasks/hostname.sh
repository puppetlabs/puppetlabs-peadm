#!/bin/bash

hostname=$(hostname -f)

# Output a JSON result for ease of Task usage in Puppet Task Plans
echo '{ "hostname": "'$hostname'" }'
