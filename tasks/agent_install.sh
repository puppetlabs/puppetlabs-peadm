#!/bin/bash

set -e

if [ -x "/opt/puppetlabs/bin/puppet" ]; then
  echo "ERROR: Puppet agent is already installed. Re-install, re-configuration, or upgrade not supported. Please uninstall the agent before running this task."
  exit 1
fi

flags=$(echo $PT_install_flags | sed -e 's/^\["*//' -e 's/"*\]$//' -e 's/", *"/ /g')

curl -k "https://${PT_server}:8140/packages/current/install.bash" | bash -s -- $flags
