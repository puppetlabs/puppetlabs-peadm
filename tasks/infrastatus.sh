#!/usr/bin/env bash
if [[ $(id -un) != 'root' ]]; then 
  echo "must be root"
  exit 1
fi


case $PT_format in
  json)
    data=$(/opt/puppetlabs/bin/puppet infra status --format=json) 
    echo "{\"output\": ${data} }" 
    ;;
  *)
    /opt/puppetlabs/bin/puppet infra status
    ;;
esac 