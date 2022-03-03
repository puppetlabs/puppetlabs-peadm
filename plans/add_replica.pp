# This plan is still in development and currently considered experimental.
#
# @api private
#
# @summary Replace a replica host for a Standard or Large architecture.
#   Supported use cases:
#   1: The existing replica is broken, we have a fresh new VM we want to provision the replica to.
#      The new replica should have the same certname as the broken one.
# @param primary_host - The hostname and certname of the primary Puppet server
# @param replica_host - The hostname and certname of the replica VM
# @param replica_postgresql_host - The hostname and certname of the host with the replica PE-PosgreSQL database. 
#   Can be a separate host in an XL architecture, or undef in Standard or Large.
plan peadm::add_replica(
  # Standard or Large
  Peadm::SingleTargetSpec           $primary_host,
  Peadm::SingleTargetSpec           $replica_host,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Common Configuration
  Optional[String] $token_file = undef,
) {

  $primary_target             = peadm::get_targets($primary_host, 1)
  $replica_target             = peadm::get_targets($replica_host, 1)
  $replica_postgresql_target  = peadm::get_targets($replica_postgresql_host, 1)

  $certdata = run_task('peadm::cert_data', $primary_target).first.value
  $primary_avail_group_letter = $certdata['extensions'][peadm::oid('peadm_availability_group')]
  $replica_avail_group_letter = $primary_avail_group_letter ? { 'A' => 'B', 'B' => 'A' }

  # replica certname + any non-certname alt-names from the primary. Make sure
  # to Handle the case where there are no alt-names in the primary's certdata.
  $dns_alt_names = [$replica_target.peadm::certname()] + (pick($certdata['dns-alt-names'], []) - $certdata['certname'])

  # This has the effect of revoking the node's certificate, if it exists
  run_command("puppet infrastructure forget ${replica_target.peadm::certname()}", $primary_target, _catch_errors => true)

  # Check for and merge csr_attributes.
  run_plan('peadm::util::insert_csr_extension_requests', $replica_target,
      extension_requests => {
        peadm::oid('peadm_role')               => 'puppet/server',
        peadm::oid('peadm_availability_group') => $replica_avail_group_letter
      }
    )

  run_task('peadm::agent_install', $replica_target,
    server        => $primary_target.peadm::certname(),
    install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:certname=${replica_target.peadm::certname()}",
      "main:dns_alt_names=${dns_alt_names.join(',')}",
    ],
  )

  # clean the cert to make the plan idempotent
  run_task('peadm::ssl_clean', $replica_target,
    certname => $replica_target.peadm::certname(),
  )

  # Manually submit a CSR
  run_task('peadm::submit_csr', $replica_target)

  # On primary, if necessary, sign the certificate request
  run_task('peadm::sign_csr', $primary_target,
    certnames => [$replica_target.peadm::certname()],
  )

  # On <replica_target>, run the puppet agent
  run_task('peadm::puppet_runonce', $replica_target)

  # On the PE-PostgreSQL server in the <replacement-avail-group-letter> group

  # Stop puppet and add the following two lines to
  # /opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf
  #  pe-puppetdb-pe-puppetdb-map <replacement-replica-fqdn> pe-puppetdb
  #  pe-puppetdb-pe-puppetdb-migrator-map <replacement-replica-fqdn> pe-puppetdb-migrator
  apply($replica_postgresql_target) {
    service { 'puppet':
      ensure => stopped,
      before => File_line['puppetdb-map', 'migrator-map'],
    }

    file_line { 'puppetdb-map':
      path => '/opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf',
      line => "pe-puppetdb-pe-puppetdb-map ${replica_target.peadm::certname()} pe-puppetdb",
    }

    file_line { 'migrator-map':
      path => '/opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf',
      line => "pe-puppetdb-pe-puppetdb-migrator-map ${replica_target.peadm::certname()} pe-puppetdb-migrator",
    }

    service { 'pe-postgresql':
      ensure    => running,
      subscribe => File_line['puppetdb-map', 'migrator-map'],
    }
  }

  # Provision the new system as a replica
  run_task('peadm::provision_replica', $primary_target,
    replica    => $replica_target.peadm::certname(),
    token_file => $token_file,

    # Race condition, where the provision command checks PuppetDB status and
    # probably gets "starting", but fails out because that's not "running".
    # Can remove flag when that issue is fixed.
    legacy     => true,
  )

  # start puppet service on postgresql host
  run_command('systemctl start puppet.service', $replica_postgresql_target)

  return("Added replica ${replica_target}")
}
