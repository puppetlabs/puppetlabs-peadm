# Recovery procedures

These instructions provide automated procedures for recovering from select failures of PE components which are managed by PEADM.

Additional manual procedures are documented in [recovery.md](recovery.md)

## Replace failed PE-PostgreSQL server (A or B side)

The procedure for replacing a failed PE-PostgreSQL server is the same regardless of which PE-PostgreSQL server is missing or if the name of the PE-PostgrSQL server is the same or different. This procedure uses the following placeholder references.

* _\<replacement-postgres-server-fqdn\>_ - The FQDN and certname of the new server being brought in to replace the failed PE-PostgreSQL server
* _\<working-postgres-server-fqdn\>_ - The FQDN and certname of the still-working PE-PostgreSQL server
* _\<failed-postgres-server-fqdn\>_ - The FQDN and certname of the failed PE-PostgreSQL server
* _\<primary-server-fqdn\>_ - The FQDN and certname of the primary Puppet server
* _\<replica-server-fqdn\>_ - The FQDN and certname of the replica Puppet server

Procedure:

1. Stop `puppet.service` on Puppet server primary and replica

        bolt task run service name=puppet.service action=stop --targets <primary-server-fqdn>,<replica-server-fqdn>

2. Temporarily set both primary and replica server nodes so that they use the remaining healthy PE-PostgreSQL server

        bolt plan run peadm::util::update_db_setting --target <primary-server-fqdn>,<replica-server-fqdn> primary_postgresql_host=<working-postgres-server-fqdn> override=true

3. Restart `pe-puppetdb.service` on Puppet server primary and replica

        bolt task run service name=pe-puppetdb.service action=restart --targets <primary-server-fqdn>,<replica-server-fqdn>

4. Purge failed PE-PostgreSQL node from PuppetDB

        bolt command run "/opt/puppetlabs/bin/puppet node purge <failed-postgres-server-fqdn>" --targets <primary-server-fqdn>

5. Run `peadm::add_database` plan to deploy replacement PE-PostgreSQL server

        bolt plan run peadm::add_database -t <replacement-postgres-server-fqdn> primary_host=<primary-server-fqdn>