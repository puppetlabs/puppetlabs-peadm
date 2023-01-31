# This plan is in development and currently considered experimental.
#
# @api private
#
# @summary Add a new compiler to a PE architecture or replace an existing one with new configuration.
# @param avail_group_letter _ Either A or B; whichever of the two letter designations the compiler is being assigned to
# @param compiler_host _ The hostname and certname of the new compiler
# @param dns_alt_names _ A comma_separated list of DNS alt names for the compiler
# @param primary_host _ The hostname and certname of the primary Puppet server
# @param primary_postgresql_host _ The hostname and certname of the PE-PostgreSQL server with availability group $avail_group_letter
plan peadm::add_compiler(
  Enum['A', 'B'] $avail_group_letter,
  Optional[String[1]] $dns_alt_names = undef,
  Peadm::SingleTargetSpec $compiler_host,
  Peadm::SingleTargetSpec $primary_host,
  Peadm::SingleTargetSpec $primary_postgresql_host,
) {
  $compiler_target           = peadm::get_targets($compiler_host, 1)
  $primary_target            = peadm::get_targets($primary_host, 1)
  $primary_postgresql_target = peadm::get_targets($primary_postgresql_host, 1)

  # Get current peadm config to determine where to setup additional rules for
  # compiler's secondary PuppetDB instances
  $peadm_config = run_task('peadm::get_peadm_config', $primary_target).first.value

  # Return the opposite server than the compiler to be added so it can be
  # configured with the appropriate rules for Puppet Server access from
  # compiler
  $replica_avail_group_letter = $avail_group_letter ? { 'A' => 'B', 'B' => 'A' }
  $replica_puppetdb = $peadm_config['role-letter']['server'][$replica_avail_group_letter]

  $replica_puppetdb_target = peadm::get_targets($replica_puppetdb, 1)

  # Stop puppet.service
  run_command('systemctl stop puppet.service', peadm::flatten_compact([
        $primary_postgresql_target,
        $replica_puppetdb_target,
  ]))

  apply($replica_puppetdb_target) {
    file_line { 'pe-puppetdb-compiler-cert-allow':
      path => '/etc/puppetlabs/puppetdb/certificate-allowlist',
      line => $compiler_target.peadm::certname(),
    }
  }

  # On the PostgreSQL server backing PuppetDB for compiler, get version number
  $psql_version = run_task('peadm::get_psql_version', $primary_postgresql_target).first.value['version']

  # Add the following two lines to /opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf
  # 
  # pe-puppetdb-pe-puppetdb-map <new-compiler-host> pe-puppetdb
  # pe-puppetdb-pe-puppetdb-migrator-map <new-compiler-host> pe-puppetdb-migrator

  apply($primary_postgresql_target) {
    file_line { 'pe-puppetdb-pe-puppetdb-map':
      path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
      line => "pe-puppetdb-pe-puppetdb-map ${compiler_target.peadm::certname()} pe-puppetdb",
    }
    file_line { 'pe-puppetdb-pe-puppetdb-migrator-map':
      path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
      line => "pe-puppetdb-pe-puppetdb-migrator-map ${compiler_target.peadm::certname()} pe-puppetdb-migrator",
    }
    file_line { 'pe-puppetdb-pe-puppetdb-read-map':
      path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
      line => "pe-puppetdb-pe-puppetdb-read-map ${compiler_target.peadm::certname()} pe-puppetdb-read",
    }
  }

  # Reload pe-postgresql.service
  run_command('systemctl reload pe-postgresql.service', $primary_postgresql_target)

  # Install the puppet agent making sure to specify an availability group letter, A or B, as an extension request.
  $dns_alt_names_flag = $dns_alt_names? {
    undef   => [],
    default => ["main:dns_alt_names=${dns_alt_names}"],
  }

  # Check for and merge csr_attributes.
  run_plan('peadm::util::insert_csr_extension_requests', $compiler_target,
    extension_requests => {
      peadm::oid('pp_auth_role')             => 'pe_compiler',
      peadm::oid('peadm_availability_group') => $avail_group_letter,
    }
  )

  # we first assume that there is no agent installed on the node. If there is, nothing will happen.
  run_task('peadm::agent_install', $compiler_target,
    server        => $primary_target.peadm::certname(),
    install_flags => $dns_alt_names_flag + [
      '--puppet-service-ensure', 'stopped',
      "main:certname=${compiler_target.peadm::certname()}",
    ],
  )

  # If necessary, manually submit a CSR
  # ignoring errors to simplify logic
  run_task('peadm::submit_csr', $compiler_target, { '_catch_errors' => true })

  # On primary, if necessary, sign the certificate request
  run_task('peadm::sign_csr', $primary_target, { 'certnames' => [$compiler_target.peadm::certname()] })

  # If there was already a signed cert, force the certificate extensions we want
  # TODO: update peadm::util::add_cert_extensions to take care of dns alt names
  run_plan('peadm::modify_certificate', $compiler_target,
    primary_host   => $primary_target.peadm::certname(),
    add_extensions => {
      peadm::oid('pp_auth_role')             => 'pe_compiler',
      peadm::oid('peadm_availability_group') => $avail_group_letter,
    },
  )

  # Source the global hiera.yaml from Primary and synchronize to new compiler
  run_plan('peadm::util::copy_file', $compiler_target,
    source_host => $primary_target,
    path        => '/etc/puppetlabs/puppet/hiera.yaml'
  )

  # On <compiler-host>, run the puppet agent
  run_task('peadm::puppet_runonce', $compiler_target)

  # On <primary_postgresql_host> run the puppet agent
  run_task('peadm::puppet_runonce', peadm::flatten_compact([
        $primary_postgresql_target,
        $replica_puppetdb_target,
  ]))

  # On <primary_postgresql_host> start puppet.service
  run_command('systemctl start puppet.service', peadm::flatten_compact([
        $primary_postgresql_target,
        $replica_puppetdb_target,
        $compiler_target,
  ]))

  return("Adding or replacing compiler ${$compiler_target.peadm::certname()} succeeded.")
}
