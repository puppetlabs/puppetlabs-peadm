#!/bin/bash -e
# This task reinstalls PE and needs to run as root.

# Uninstall PE if installed
if [[ "$PT_uninstall" == true ]]; then
  /opt/puppetlabs/bin/puppet-enterprise-uninstaller -p -d -y || true
fi

# Download PE
INSTALLER="puppet-enterprise-${PT_version}-${PT_arch}"
curl -O "https://s3.amazonaws.com/pe-builds/released/${PT_version}/${INSTALLER}.tar.gz"
tar xf "${INSTALLER}.tar.gz"

# Install PE. We need to pass "y" through stdin since the flag -y requires pe.conf to be present.
cd $INSTALLER
echo 'y' | ./puppet-enterprise-installer
