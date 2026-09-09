#!/bin/bash

# Try and ensure locale is correctly configured
[ -z "${LANG}" ] && export LANG=$(localectl status | sed -n 's/.* LANG=\(.*\)/\1/p')

if [ ! -f "${PT_installer_dir}/puppet-enterprise-installer" ]; then
	echo "Puppet Enterprise installer not found at ${PT_installer_dir}/puppet-enterprise-installer"
	exit 1
fi

/bin/bash "${PT_installer_dir}/puppet-enterprise-installer" -y -c "$PT_peconf"

# The exit code of the installer script will be the exit code of the task
exit_code=$?

if [ "$PT_puppet_service_ensure" = "stopped" ]; then
	systemctl stop puppet.service
fi

exit $exit_code
