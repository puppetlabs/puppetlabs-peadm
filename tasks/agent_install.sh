#!/bin/bash

set -e

if [ -x "/opt/puppetlabs/bin/puppet" ]; then
  echo "WARNING: Puppet agent is already installed. Re-install, re-configuration, or upgrade not supported and might fail."
fi

flags=$(echo "$PT_install_flags" | sed -e 's/^\["*//' -e 's/"*\]$//' -e 's/", *"/ /g')

curl -k "https://${PT_server}:8140/packages/current/install.bash" | bash -s -- $flags
