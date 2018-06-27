#!/bin/bash

mkdir -p /etc/puppetlabs/puppet
cat <<EOF > /etc/puppetlabs/puppet/csr_attributes.yaml
$PT_csr_attributes_yaml
EOF

# This stanza configures PuppetDB to quickly fail on start. This is desirable
# in situations where PuppetDB WILL fail, such as when PostgreSQL is not yet
# configured, and we don't want to let PuppetDB wait five minutes before
# giving up on it.
if [ "$PT_shortcircuit_puppetdb" = "true" ]; then
	mkdir /etc/systemd/system/pe-puppetdb.service.d
	cat > /etc/systemd/system/pe-puppetdb.service.d/short-circuit.conf <<-EOF
		[service]
		TimeoutStartSec=1
		TimeoutStopSec=1
	EOF
fi

cd $(dirname "$PT_tarball")
mkdir puppet-enterprise && tar -xzf "$PT_tarball" -C puppet-enterprise --strip-components 1
./puppet-enterprise/puppet-enterprise-installer -c "$PT_peconf"

if [ "$PT_shortcircuit_puppetdb" = "true" ]; then
	rm /etc/systemd/system/pe-puppetdb.service.d/short-circuit.conf
fi
