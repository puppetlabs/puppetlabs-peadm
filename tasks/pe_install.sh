#!/bin/bash
source "$(dirname $0)/../../peadm/files/task_helper.sh"

# Try and ensure locale is correctly configured
[ -z "${LANG}" ] && export LANG=$(localectl status | sed -n 's/.* LANG=\(.*\)/\1/p')

# This stanza configures PuppetDB to quickly fail on start. This is desirable
# in situations where PuppetDB WILL fail, such as when PostgreSQL is not yet
# configured, and we don't want to let PuppetDB wait five minutes before
# giving up on it.
if [ "$PT_install_extra_large" = "true" ]; then
	mkdir /etc/systemd/system/pe-puppetdb.service.d
	cat > /etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf <<-EOF
		[Service]
		TimeoutStartSec=1
		TimeoutStopSec=1
		Restart=no
	EOF
	systemctl daemon-reload
fi

tgzdir=$(dirname "$PT_tarball")
pedir=$(tar -tf "$PT_tarball" | head -n 1 | xargs dirname)

if file "$PT_tarball" | grep -q gzip; then
  tar_options="-xzf"
else
  tar_options="-xf"
fi 

tar -C "$tgzdir" "$tar_options" "$PT_tarball"

if [ ! -z "$PT_peconf" ]; then
	/bin/bash "${tgzdir}/${pedir}/puppet-enterprise-installer" -y -c "$PT_peconf"
else
	/bin/bash "${tgzdir}/${pedir}/puppet-enterprise-installer" -y
fi

# The exit code of the installer script will be the exit code of the task
exit_code=$?

if [ "$PT_install_extra_large" = "true" ]; then
	systemctl stop pe-puppetdb.service
	rm /etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf
	systemctl daemon-reload
fi

if [ "$PT_puppet_service_ensure" = "stopped" ]; then
	systemctl stop puppet.service
fi

# In an extra large install, the installer is known to exit with code 1, even
# on an otherwise successful install, because PuppetDB cannot start yet. The
# task should indicate successful completion even if the exit code is 1, as
# long as some basic "did it install?" health checks pass.
if [ "$PT_install_extra_large" = "true" ]; then
	for svc in pe-puppetserver pe-orchestration-services pe-console-services; do
		systemctl is-active --quiet $svc.service || exit $exit_code
	done
	exit 0
else
	# Exit with the installer script's exit code
	exit $exit_code
fi
