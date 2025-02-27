# Recovery procedures

These instructions provide automated procedures for recovering from select failures of PE components which are managed by PEADM.

Manual procedures are documented in [recovery.md](recovery.md)

## Recover from failed Puppet primary server

1. Promote the replica ([official docs](https://puppet.com/docs/pe/2019.8/dr_configure.html#dr-promote-replica))
2. [Replace missing or failed replica Puppet server](#replace-missing-or-failed-replica-puppet-server)

## Replace missing or failed replica Puppet server

This procedure uses the following placeholder references.

* _\<primary-server-fqdn\>_ - The FQDN and certname of the Puppet primary server
* _\<replica-postgres-server-fqdn\>_ - The FQDN and certname of the PE-PostgreSQL server which resides in the same availability group as the replacement replica Puppet server
* _\<replacement-replica-fqdn\>_ - The FQDN and certname of the replacement replica Puppet server

1. Run `peadm::add_replica` plan to deploy replacement replica Puppet server
    1. For Standard and Large deployments

                bolt plan run peadm::add_replica primary_host=<primary-server-fqdn> replica_host=<replacement-replica-fqdn>

    2. For Extra Large deployments

                bolt plan run peadm::add_replica primary_host=<primary-server-fqdn> replica_host=<replacement-replica-fqdn> replica_postgresql_host=<replica-postgres-server-fqdn>

## Replace failed PE-PostgreSQL server (A or B side)

The procedure for replacing a failed PE-PostgreSQL server is the same regardless of which PE-PostgreSQL server is missing or whether the name of the PE-PostgreSQL server is the same or different. This procedure uses the following placeholder references.

* _\<replacement-postgres-server-fqdn\>_ - The FQDN and certname of the new server being brought in to replace the failed PE-PostgreSQL server
* _\<working-postgres-server-fqdn\>_ - The FQDN and certname of the still-working PE-PostgreSQL server
* _\<failed-postgres-server-fqdn\>_ - The FQDN and certname of the failed PE-PostgreSQL server
* _\<primary-server-fqdn\>_ - The FQDN and certname of the Puppet primary server
* _\<replica-server-fqdn\>_ - The FQDN and certname of the replica Puppet server

Procedure:

1. Run the `peadm::replace_failed_postgresql` plan to replace the failed PE-PostgreSQL server:

        bolt plan run peadm::replace_failed_postgresql \
                primary_host=<primary-server-fqdn> \
                replica_host=<replica-server-fqdn> \
                working_postgresql_host=<working-postgres-server-fqdn> \
                failed_postgresql_host=<failed-postgres-server-fqdn> \
                replacement_postgresql_host=<replacement-postgres-server-fqdn>

## Replace failed replica Puppet server AND failed replica PE-PostgreSQL server

This procedure uses the following placeholder references.

* _\<primary-server-fqdn\>_ - The FQDN and certname of the Puppet primary server
* _\<failed-replica-fqdn\>_ - The FQDN and certname of the failed replica Puppet server

1. Ensure the old replica server is forgotten.

        bolt command run "/opt/puppetlabs/bin/puppet infrastructure forget <failed-replica-fqdn>" --targets <primary-server-fqdn>

2. [Replace failed PE-PostgreSQL server (A or B side)](#replace-failed-pe-postgresql-server-a-or-b-side)
3. [Replace missing or failed replica Puppet server](#replace-missing-or-failed-replica-puppet-server)

## Add or replace compilers

This procedure uses the following placeholder references.

* _\<avail-group-letter\>_ - Either A or B; whichever of the two letter designations the compiler is being assigned to
* _\<compiler-hosts\>_ - A comma-separated list of FQDN and certname of the new compiler(s)
* _\<dns-alt-names\>_ - A comma-separated list of DNS alt names for the compiler
* _\<primary-server-fqdn\>_ - The FQDN and certname of the Puppet primary server
* _\<postgresql-server-fqdn\>_ - The FQDN and certname of the PE-PostgreSQL server with availability group _\<avail-group-letter\>_

Procedure:

1. Run the `peadm::add_compilers` plan to add the compilers:

        bolt plan run peadm::add_compilers \
                primary_host=<primary-server-fqdn> \
                compiler_hosts=<compiler-hosts> \
                avail_group_letter=<avail-group-letter> \
                dns_alt_names=<dns-alt-names> \
                primary_postgresql_host=<postgresql-server-fqdn>

Please note, the optional parameters and values of the plan are as follows:

<!-- table -->

| Parameter                 | Default value | Description                                                                                                                    |
| ------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `avail_group_letter`      | `A`           | By default, each compiler will be added to the primary group A.                                                                |
| `dns_alt_names`           | `undef`       |                                                                                                                                |
| `primary_postgresql_host` | `undef`       | By default, this will pre-populate to the required value depending on whether your architecture contains HA and or external databases. |

For more information around adding compilers to your infrastructure [Expanding Your Deployment](expanding.md#adding-compilers-with-peadmadd_compiler)