#!/usr/bin/env bash

# For more information about what this task can return see the API
# https://puppet.com/docs/puppetserver/latest/status-api/v1/services.html
# Note: if you pass in a service name you will get only the status of that 
#       service.
# This task is meant to be run on the puppetserver which is why localhost
# is used as the hostname.
service=$PT_service
if [[ $service == 'all' ]]; then
  out=$(curl https://localhost:8140/status/v1/services -k -s)
else
  out=$(curl -k -s https://localhost:8140/status/v1/services/${service})
fi

code=$?
echo $out
exit $code
