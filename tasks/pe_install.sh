#!/bin/bash

mkdir -p /etc/puppetlabs/puppet
cat "$PT_csr_attributes_yaml" > /etc/puppetlabs/puppet/csr_attributes.yaml

cd $(dirname "$PT_tarball")
mkdir puppet-enterprise && tar -xzf "$PT_tarball" -C puppet-enterprise --strip-components 1
./puppet-enterprise/puppet-enterprise-installer -c "$PT_peconf"
