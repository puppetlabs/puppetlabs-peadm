# This plan is in development and currently considered experimental.
#
# @api private
#
# @summary Destructively (re)populates a new or existing database with the contents or a known good source
# @param source_host _ The hostname of the database containing data
plan peadm::subplans::db_populate(
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $source_host,
) {
  $source_target      = peadm::get_targets($source_host, 1)
  $destination_target = peadm::get_targets($targets, 1)

  # Always ensure Puppet is stopped or it'll remove rules that allow replication
  run_command('systemctl stop puppet.service', peadm::flatten_compact([
        $source_target,
        $destination_target,
  ]))

  # Retrieve source's PSQL version
  $psql_version = run_task('peadm::get_psql_version', $source_target).first.value['version']

  # Determine clientcert setting
  $clientcert = $psql_version ? {
    '14'    => 'verify-full',
    default => 1
  }

  # Add the following two lines to /opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf
  #
  # These lines allow connections from destination by pg_basebackup to replicate
  # content
  apply($source_target) {
    file_line { 'replication-pe-ha-replication-map':
      path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
      line => "replication-pe-ha-replication-map ${destination_target.peadm::certname()} pe-ha-replication",
    }
    file_line { 'replication-pe-ha-replication-ipv4':
      path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_hba.conf",
      line => "hostssl replication    pe-ha-replication 0.0.0.0/0  cert  map=replication-pe-ha-replication-map  clientcert=${clientcert}",
    }
    file_line { 'replication-pe-ha-replication-ipv6':
      path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_hba.conf",
      line => "hostssl replication    pe-ha-replication ::/0       cert  map=replication-pe-ha-replication-map  clientcert=${clientcert}",
    }
  }

  # Reload pe-postgresql to activate replication rules
  run_command('systemctl reload pe-postgresql.service', $source_target)

  # Save existing certificates to use for authentication to source. Can not use
  # certs stored in /etc/puppetlabs/puppet/ssl because we will run pg_basebackup
  # as pe-postgres user, which lacks access
  run_command("mv /opt/puppetlabs/server/data/postgresql/${psql_version}/data/certs /opt/puppetlabs/server/data/pg_certs", $destination_target)# lint:ignore:140chars

  # pg_basebackup requires an entirely empty data directory
  run_command('rm -rf /opt/puppetlabs/server/data/postgresql/*', $destination_target)
  $pg_basebackup = @("PGBASE")
    runuser -u pe-postgres -- \
      /opt/puppetlabs/server/bin/pg_basebackup \
        -D /opt/puppetlabs/server/data/postgresql/${psql_version}/data \
        -d "host=${source_host}
            user=pe-ha-replication
            sslmode=verify-full
            sslcert=/opt/puppetlabs/server/data/pg_certs/_local.cert.pem
            sslkey=/opt/puppetlabs/server/data/pg_certs/_local.private_key.pem
            sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem"
    | - PGBASE
  run_command($pg_basebackup, $destination_target)

  # Delete the saved certs, they'll be properly re-populated by an agent run
  run_command('rm -rf /opt/puppetlabs/server/data/pg_certs', $destination_target)

  # Start pe-postgresql.service
  run_command('systemctl start pe-postgresql.service', $destination_target)

  # Delete the previously add replication rules to prevent Puppet restarting
  # thing later
  apply($source_target) {
    file_line { 'replication-pe-ha-replication-map':
      ensure => absent,
      path   => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
      line   => "replication-pe-ha-replication-map ${destination_target.peadm::certname()} pe-ha-replication",
    }
    file_line { 'replication-pe-ha-replication-ipv4':
      ensure => absent,
      path   => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_hba.conf",
      line   => "hostssl replication    pe-ha-replication 0.0.0.0/0  cert  map=replication-pe-ha-replication-map  clientcert=${clientcert}",
    }
    file_line { 'replication-pe-ha-replication-ipv6':
      ensure => absent,
      path   => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_hba.conf",
      line   => "hostssl replication    pe-ha-replication ::/0       cert  map=replication-pe-ha-replication-map  clientcert=${clientcert}",
    }
  }

  # Reload pe-postgresql to revoke replication rules
  run_command('systemctl reload pe-postgresql.service', $source_target)

  return("Population of ${$destination_target.peadm::certname()} with data from s${$source_target.peadm::certname()} succeeded.")
}
