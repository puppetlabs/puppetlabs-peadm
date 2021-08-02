#!/bin/bash

# Uninstalling PE with the following flags
# For more information about the uninstaller
#  and the command-line flags, visit:
#  https://puppet.com/docs/pe/2019.8/uninstalling.html

if [ -x "$(command -v /opt/puppetlabs/bin/puppet-enterprise-uninstaller)" ]; then
    /opt/puppetlabs/bin/puppet-enterprise-uninstaller -d -p -y
else
    echo 'Error: puppet-enterprise-uninstaller is not available on this target.'
    exit 1
fi
