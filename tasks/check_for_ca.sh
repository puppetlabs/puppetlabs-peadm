#!/bin/bash

# Puppet Task Name: check_for_ca
#
# Explected possible inputs:
#   $PT_master_replica_host
#   $PT_puppetdb_database_host
#   $PT_puppetdb_database_replica_host
#   $PT_compiler_hosts
#

# A function to check for and remove signed certs for the infra
function check_for_cert()
{
  cert="/etc/puppetlabs/puppet/ssl/ca/signed/${1}.pem"
  if [ -f $cert ];
  then
    echo "Removing existing signed cert for ${1}"
    /bin/rm -rf $cert
  fi
}


# Check to see if pe-puppetserver has been installed
if [ -f '/opt/puppetlabs/puppetserver/server/bin/puppetserver']
then
  echo "Puppetserver has been installed, skipping existing CA and cert check."
else
  # if pe-puppetserver has not been installed yet then 
  # we continue to check for a restored CA and certs.
  if [ -n "${PT_master_replica_host}" ]; then check_for_cert $PT_master_replica_host; fi
  if [ -n "${PT_puppetdb_database_host}" ]; then check_for_cert $PT_puppetdb_database_host; fi
  if [ -n "${PT_puppetdb_database_replica_host}" ]; then check_for_cert $PT_puppetdb_database_replica_host; fi

  # Beause the compiler array is expected to be json formatted, 
  # we need to do some conversion work.
  if [ -n "${PT_compiler_hosts}" ];
  then
    read -a compiler_array <<< $( /bin/echo $PT_compiler_hosts | /bin/tr \[\]\", ' ' )
    for i in "${compiler_array[@]}";
    do 
      check_for_cert $i
    done
  fi
fi