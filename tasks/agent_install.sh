#!/bin/bash

set -e

flags=$(echo $PT_install_flags | sed -e 's/^\["//' -e 's/\"]$//' -e 's/", *"/ /g')

if [ -f /etc/puppetlabs/puppet/csr_attributes.yaml ]; then
  # csr_attributes is already installed on the server, exclude those
  # options from the command line flags.
  read -a flags_array <<< $flags
  for member in "${flags_array[@]}"; do
    if [[ $member =~ ^extension ]]; then
      flags_array=("${flags_array[@]/$member}")
    fi
  done
  flags="${flags_array[@]}"
fi

curl -k "https://${PT_server}:8140/packages/current/install.bash" | bash -s -- $flags
