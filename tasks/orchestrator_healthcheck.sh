#!/bin/bash

g_certname=$(/opt/puppetlabs/bin/puppet config print certname)

check()
{
  curl "https://${g_certname}:8143/status/v1/simple" \
      --cert "/etc/puppetlabs/puppet/ssl/certs/${g_certname}.pem" \
      --key "/etc/puppetlabs/puppet/ssl/private_keys/${g_certname}.pem" \
      --cacert "/etc/puppetlabs/puppet/ssl/certs/ca.pem" \
      --silent \
      --show-error \
      --fail
}

n=0
until [ $n -ge 10 ]
do
  check && break
  n=$[$n+1]
  sleep 3
done
