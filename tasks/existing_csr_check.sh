#!/bin/sh

# Puppet Task Name: existing_csr_check
#

if [ -f /etc/puppetlabs/puppet/csr_attributes.yaml ]; then
  exit 1
else
  exit 0
fi