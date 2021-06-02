# Recovery procedures

These instructions all assume that the failed server is destroyed, and being replaced with a completely new VM.

The new system needs to be provisioned with the same certificate name as the system it is replacing.

## Recover from failed primary Puppet server

1. Promote the replica ([official docs](https://puppet.com/docs/pe/2019.8/dr_configure.html#dr-promote-replica))
2. Replace missing replica server (same as [Replace missing or failed replica Puppet server](#replace-missing-or-failed-replica-puppet-server) below)

## Replace missing or failed replica Puppet server

This procedure uses the following placeholder references.

* _\<primary-server-fqdn\>_ - The FQDN and certname of the primary Puppet server
* _\<replacement-replica-fqdn\>_ - The FQDN and certname of the replacement replica Puppet server
* _\<replacement-avail-group-letter\>_ - Either A or B; whichever of the two letter designations is appropriate for the server being replaced. It will be the opposite of the primary server.

1. Ensure the old replica server is forgotten.

        puppet infrastructure forget <replacement-replica-fqdn>

2. Install the Puppet agent on the replacement replica

        curl -k https://<primary-server-fqdn>:8140/packages/current/install.bash \
          | bash -s -- \
              main:certname=<replacement-replica-fqdn> \
              extension_requests:1.3.6.1.4.1.34380.1.1.9812=puppet/server \
              extension_requests:1.3.6.1.4.1.34380.1.1.9813=<replacement-avail-group-letter>

        puppet agent -t

3. On the PE-PostgreSQL server in the _\<replacement-avail-group-letter\>_ group
    1. Stop puppet.service
    2. Add the following two lines to /opt/puppetlabs/server/data/postgresql/11/data/pg\_ident.conf

            pe-puppetdb-pe-puppetdb-map <replacement-replica-fqdn> pe-puppetdb
            pe-puppetdb-pe-puppetdb-migrator-map <replacement-replica-fqdn> pe-puppetdb-migrator

    3. Restart pe-postgresql.service
3. Provision the new system as a replica

        puppet infrastructure provision replica <replacement-replica-fqdn> --topology mono-with-compile --skip-agent-config --enable

4. On the PE-PostgreSQL server in the _\<replacement-avail-group-letter\>_ group, start puppet.service

## Replace failed PE-PostgreSQL server (A or B side)

The procedure for replacing a failed PE-PostgreSQL server is the same regardless of which PE-PostgreSQL server is missing. This procedure uses the following placeholder references.

* _\<replacement-postgres-server-fqdn\>_ - The FQDN and certname of the new server being brought in to replace the failed PE-PostgreSQL server
* _\<working-postgres-server-fqdn\>_ - The FQDN and certname of the still-working PE-PostgreSQL server
* _\<replacement-avail-group-letter\>_ - Either A or B; whichever of the two letter designations is appropriate for the server being replaced. It will be the opposite of the still-working PE-PostgreSQL server
* _\<primary-server-fqdn\>_ - The FQDN and certname of the primary Puppet server

Procedure:

1. Clean the old _\<replacement-postgres-server-fqdn\>_ cert so that the restored node will be able to request a new one with the same name

        puppetserver ca clean --certname <replacement-server-fqdn>

2. Stop puppet.service and pe-puppetdb.service on all compilers in the _\<replacement-avail-group-letter\>_ group, and on whichever Puppet server (primary or replica) is in the _\<replacement-avail-group-letter\>_ group.
3. Pre-seed the following configuration files on the new _\<replacement-postgres-server-fqdn\>_ node, before installing PE.
    * /etc/puppetlabs/puppet/puppet.conf

            [main]
            certname = <replacement-postgres-server-fqdn>

    * /etc/puppetlabs/puppet/csr\_attributes.yaml

            ---
            extension_requests:
              1.3.6.1.4.1.34380.1.1.9812: puppet/puppetdb-database
              1.3.6.1.4.1.34380.1.1.9813: <replacement-avail-group-letter>

    * /tmp/pe.conf

            {
              "console_admin_password": "not used",
              "puppet_enterprise::puppet_master_host": "<primary-server-fqdn>",
              "puppet_enterprise::database_host": "<replacement-postgres-server-fqdn>",
              "puppet_enterprise::profile::database::puppetdb_hosts": [
                "<primary-server-fqdn>",
                "<replica-server-fqdn>"
              ]
            }

4. Download the appropriate version of the Puppet Enterprise installer to _\<replacement-postgres-server-fqdn\>_, and run it. Use the pe.conf file created in the previous step.

        ./puppet-enterprise-installer -c /tmp/pe.conf

5. Run `puppet agent -t` on _\<replacement-postgres-server-fqdn\>_

Running this procedure should re-attach _\<replacement-postgres-server-fqdn\>_ to the cluster. It will not have restored its database, however.

**pg_basebackup:** 

On _\<working-postgres-server-fqdn\>_:

1. Stop puppet.

        systemctl stop puppet

2. Add this line to /opt/puppetlabs/server/data/postgresql/11/data/pg\_ident.conf

        replication-pe-ha-replication-map <replacement-postgres-server-fqdn> pe-ha-replication

3. Add these lines to /opt/puppetlabs/server/data/postgresql/11/data/pg\_hba.conf

        # REPLICATION RESTORE PERMISSIONS
        hostssl replication    pe-ha-replication 0.0.0.0/0  cert  map=replication-pe-ha-replication-map  clientcert=1
        hostssl replication    pe-ha-replication ::/0       cert  map=replication-pe-ha-replication-map  clientcert=1

4. Reload pe-postgresql.service

        systemctl reload pe-postgresql.service

On _\<replacement-postgres-server-fqdn\>_:

Run the following commands.

```
systemctl stop puppet.service pe-postgresql.service

mv /opt/puppetlabs/server/data/postgresql/11/data/certs /opt/puppetlabs/server/data/pg_certs

rm -rf /opt/puppetlabs/server/data/postgresql/*

runuser -u pe-postgres -- \
  /opt/puppetlabs/server/bin/pg_basebackup \
    -D /opt/puppetlabs/server/data/postgresql/11/data \
    -d "host=<working-postgres-server-fqdn>
        user=pe-ha-replication
        sslmode=verify-full
        sslcert=/opt/puppetlabs/server/data/pg_certs/_local.cert.pem
        sslkey=/opt/puppetlabs/server/data/pg_certs/_local.private_key.pem
        sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem"

rm -rf /opt/puppetlabs/server/data/pg_certs

systemctl start puppet.service pe-postgresql.service

puppet agent -t
```

On _\<working-postgres-server-fqdn\>_:

Start puppet again and run it to remove the replication configs.

```
systemctl start puppet.service
puppet agent -t
```

**Finalize:**

After you finish the procedure and pg\_basebackup, restart puppetdb.service and puppet.service first on whichever Puppet server (primary or replica) is in the _\<replacement-avail-group-letter\>_ group, then on all the compilers in the _\<replacement-avail-group-letter\>_ group.

## Replace failed replica puppet server AND failed replica pe-postgresql server

1. [Replace failed PE-PostgreSQL server (A or B side)](#replace-failed-pe-postgresql-server-a-or-b-side)
2. [Replace missing or failed replica Puppet server](#replace-missing-or-failed-replica-puppet-server)

## Add or replace compiler

This procedure uses the following placeholder references.

* _\<avail-group-letter\>_ - Either A or B; whichever of the two letter designations the compiler is being assigned to
* _\<new-compiler-fqdn\>_ - The FQDN and certname of the new compiler
* _\<dns-alt-names\>_ - A comma-separated list of DNS alt names for the compiler
* _\<primary-server-fqdn\>_ - The FQDN and certname of the primary Puppet server
* _\<postgresql-server-fqdn\>_ - The FQDN and certname of the PE-PostgreSQL server with availability group _\<avail-group-letter\>_

1. On _\<postgresql-server-fqdn\>_:
    1. Stop puppet.service
    2. Add the following two lines to /opt/puppetlabs/server/data/postgresql/11/data/pg\_ident.conf

            pe-puppetdb-pe-puppetdb-map <new-compiler-fqdn> pe-puppetdb
            pe-puppetdb-pe-puppetdb-migrator-map <new-compiler-fqdn> pe-puppetdb-migrator

    3. Reload pe-postgresql.service

2. On _\<new-compiler-fqdn\>_:
    1. Install the puppet agent making sure to specify an availability group letter, A or B, as an extension request.

            curl -k https://<primary-server-fqdn>:8140/packages/current/install.bash \
              | sudo bash -s -- \
                  extension_requests:pp_auth_role=pe_compiler \
                  extension_requests:1.3.6.1.4.1.34380.1.1.9813=<avail-group-letter> \
                  main:dns_alt_names=<dns-alt-names> \
                  main:certname=<new-compiler-fqdn>

    2. If necessary, manually submit a CSR

            puppet ssl submit_request

3. On _\<primary-server-fqdn\>_, if necessary, sign the certificate request.

        puppetserver ca sign --certname <new-compiler-certname>

4. On _\<new-compiler-fqdn\>_, run the puppet agent

        puppet agent -t

5. On _\<postgresql-server-fqdn\>_:
    1. Run the puppet agent

            puppet agent -t

    2. Start puppet.service
