# @api public
#
# @summary Add new compilers to a PE architecture or replace an existing with new configuration.
# @param avail_group_letter _ Either A or B; whichever of the two letter designations the compilers are being assigned to
# @param compiler_hosts _ The hostnames and certnames of the new compilers
# @param dns_alt_names _ An array of strings, where each string is a comma-separated list of DNS alt names for the compilers. Order matters; if a compiler doesn't need dns_alt_names, use "undef" as string.
# @param primary_host _ The hostname and certname of the primary Puppet server
# @param primary_postgresql_host _ The hostname and certname of the PE-PostgreSQL server with availability group $avail_group_letter
plan peadm::add_compilers(
  Enum['A', 'B'] $avail_group_letter = 'A' ,
  Optional[Array[String[1]]] $dns_alt_names = undef,
  TargetSpec $compiler_hosts,
  Peadm::SingleTargetSpec $primary_host,
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
) {
  $compiler_targets          = peadm::get_targets($compiler_hosts)
  $primary_target            = peadm::get_targets($primary_host, 1)

  # Get current peadm config to determine where to setup additional rules for
  # compiler's secondary PuppetDB instances
  $peadm_config = run_task('peadm::get_peadm_config', $primary_target).first.value

  if $primary_postgresql_host == undef {
    # get the external PostgreSQL host for the specified availability group
    $external_postgresql_host = $avail_group_letter ? {
      'A'     => $peadm_config['params']['primary_postgresql_host'],
      default => $peadm_config['params']['replica_postgresql_host'],
    }

    # If the external_postgresql_host is undef, use the server for that availability group
    $postgresql_host = $external_postgresql_host ? {
      undef   => $peadm_config['role-letter']['server'][$avail_group_letter],
      default => $external_postgresql_host,
    }

    if $postgresql_host == undef {
      fail_plan("No PostgreSQL host found for availability group ${avail_group_letter}")
    }

    $primary_postgresql_target = peadm::get_targets($postgresql_host, 1)
  } else {
    $primary_postgresql_target = peadm::get_targets($primary_postgresql_host, 1)
  }

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
    $compiler_targets.each |$compiler_target| {
      file_line { "pe-puppetdb-compiler-cert-allow-${compiler_target.peadm::certname()}":
        path => '/etc/puppetlabs/puppetdb/certificate-allowlist',
        line => $compiler_target.peadm::certname(),
      }
    }
  }

  # On the PostgreSQL server backing PuppetDB for compiler, get version number
  $psql_version = run_task('peadm::get_psql_version', $primary_postgresql_target).first.value['version']

  # Add the following two lines to /opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf
  # 
  # pe-puppetdb-pe-puppetdb-map <new-compiler-host> pe-puppetdb
  # pe-puppetdb-pe-puppetdb-migrator-map <new-compiler-host> pe-puppetdb-migrator

  apply($primary_postgresql_target) {
    $compiler_targets.each |$compiler_target| {
      file_line { "pe-puppetdb-pe-puppetdb-map-${compiler_target.peadm::certname()}":
        path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
        line => "pe-puppetdb-pe-puppetdb-map ${compiler_target.peadm::certname()} pe-puppetdb",
      }
      file_line { "pe-puppetdb-pe-puppetdb-migrator-map-${compiler_target.peadm::certname()}":
        path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
        line => "pe-puppetdb-pe-puppetdb-migrator-map ${compiler_target.peadm::certname()} pe-puppetdb-migrator",
      }
      file_line { "pe-puppetdb-pe-puppetdb-read-map-${compiler_target.peadm::certname()}":
        path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
        line => "pe-puppetdb-pe-puppetdb-read-map ${compiler_target.peadm::certname()} pe-puppetdb-read",
      }
    }
  }

  # Reload pe-postgresql.service
  run_command('systemctl reload pe-postgresql.service', $primary_postgresql_target)

  $compiler_targets_with_dns_alt_names = $compiler_targets.map |$index, $compiler_target| {
    $current_dns_alt_names = $dns_alt_names ? {
      undef   => undef,
      default => $dns_alt_names[$index] ? {
        'undef'   => undef,
        default => $dns_alt_names[$index],
      }
    }

    [$current_dns_alt_names, $compiler_target]
  }

  # Install agent (if required) and regenerate agent certificate to add required data with peadm::subplans::component_install
  parallelize($compiler_targets_with_dns_alt_names) |$pair| {
    $current_dns_alt_names = $pair[0]
    $compiler_target = $pair[1]

    run_plan('peadm::subplans::component_install', $compiler_target,
      primary_host       => $primary_target,
      avail_group_letter => $avail_group_letter,
      dns_alt_names      => $current_dns_alt_names,
      role               => 'pe_compiler',
    )

    # Source the global hiera.yaml from Primary and synchronize to new compiler
    run_plan('peadm::util::copy_file', $compiler_target,
      source_host => $primary_target,
      path        => '/etc/puppetlabs/puppet/hiera.yaml'
    )

    # On <compiler-host>, run puppet agent
    run_task('peadm::puppet_runonce', $compiler_target)
  }

  # On <primary_postgresql_host>, run puppet agent
  run_task('peadm::puppet_runonce', $primary_postgresql_target)

  # On <replica_puppetdb_target>, run puppet agent
  run_task('peadm::puppet_runonce', $replica_puppetdb_target)

  # On <primary_postgresql_host>, start puppet.service
  run_command('systemctl start puppet.service', peadm::flatten_compact([
        $primary_postgresql_target,
        $replica_puppetdb_target,
        $compiler_targets,
  ]))

  $compiler_names = $compiler_targets.map |$compiler_target| { $compiler_target.peadm::certname() }.join(', ')
  return("Adding or replacing compiler(s) ${compiler_names} succeeded.")
}
