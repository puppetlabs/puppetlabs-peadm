# @summary Configure first-time classification and HA setup
#
plan pe_xl::unit::configure (
  # Large
  Pe_xl::SingleTargetSpec           $master_host,
  Optional[TargetSpec]              $compiler_hosts = undef,
  Optional[Pe_xl::SingleTargetSpec] $master_replica_host = undef,

  # Extra Large
  Optional[Pe_xl::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Pe_xl::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String           $compiler_pool_address = $master_host,
  Optional[String] $token_file = undef,
  Optional[String] $deploy_environment = undef,

  # Other
  String           $stagingdir = '/tmp',
) {
  # Convert inputs into targets.
  $master_target                    = pe_xl::get_targets($master_host, 1)
  $master_replica_target            = pe_xl::get_targets($master_replica_host, 1)
  $puppetdb_database_replica_target = pe_xl::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = pe_xl::get_targets($compiler_hosts)
  $puppetdb_database_target         = $puppetdb_database_host ? {
    undef   => $master_target,
    default => pe_xl::get_targets($puppetdb_database_host, 1)
  }

  # Ensure input valid for a supported architecture
  $arch = pe_xl::validate_architecture(
    $master_host,
    $master_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  # Set up the console node groups to configure the various hosts in their
  # roles

  # Pending resolution of Bolt GH-1244, Target objects and their methods are
  # not accessible inside apply() blocks. Work around the limitation for now
  # by using string variables calculated outside the apply block. The
  # commented-out values should be used once GH-1244 is resolved.

  # WORKAROUND: GH-1244
  $master_host_string = $master_target.pe_xl::target_host()
  $master_replica_host_string = $master_replica_target.pe_xl::target_host()
  $puppetdb_database_host_string = $puppetdb_database_target.pe_xl::target_host()
  $puppetdb_database_replica_host_string = $puppetdb_database_replica_target.pe_xl::target_host()

  apply($master_target) {
    # Necessary to give the sandboxed Puppet executor the configuration
    # necessary to connect to the classifier`
    file { 'node_manager.yaml':
      ensure   => file,
      mode     => '0644',
      path     => Deferred('pe_xl::node_manager_yaml_location'),
      content  => epp('pe_xl/node_manager.yaml.epp', {
        server => $master_host_string,
      }),
    }

    class { 'pe_xl::setup::node_manager':
      # WORKAROUND: GH-1244
      master_host                    => $master_host_string, # $master_target.pe_xl::target_host(),
      master_replica_host            => $master_replica_host_string, # $master_replica_target.pe_xl::target_host(),
      puppetdb_database_host         => $puppetdb_database_host_string, # $puppetdb_database_target.pe_xl::target_host(),
      puppetdb_database_replica_host => $puppetdb_database_replica_host_string, # $puppetdb_database_replica_target.pe_xl::target_host(),
      compiler_pool_address          => $compiler_pool_address,
      require                        => File['node_manager.yaml'],
    }
  }

  # Run Puppet in no-op on the compilers so that their status in PuppetDB
  # is updated and they can be identified by the puppet_enterprise module as
  # CMs
  run_task('pe_xl::puppet_runonce', pe_xl::flatten_compact([
    $compiler_targets,
    $master_replica_target,
  ]),
    noop => true,
  )

  # Run Puppet on the PuppetDB Database hosts to update their auth
  # configuration to allow the compilers to connect
  run_task('pe_xl::puppet_runonce', pe_xl::flatten_compact([
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
  ]))

  # Run Puppet on the master to ensure all services configured and
  # running in prep for provisioning the replica. This is done separately so
  # that a service restart of pe-puppetserver doesn't cause Puppet runs on
  # other nodes to fail.
  run_task('pe_xl::puppet_runonce', $master_target)

  if $arch['high-availability'] {
    # Run the PE Replica Provision
    run_task('pe_xl::provision_replica', $master_target,
      master_replica => $master_replica_target.pe_xl::target_host(),
      token_file     => $token_file,
    )

    # Run the PE Replica Enable
    run_task('pe_xl::enable_replica', $master_target,
      master_replica => $master_replica_target.pe_xl::target_host(),
      token_file     => $token_file,
    )
  }

  # Run Puppet everywhere to pick up last remaining config tweaks
  run_task('pe_xl::puppet_runonce', pe_xl::flatten_compact([
    $master_target,
    $puppetdb_database_target,
    $compiler_targets,
    $master_replica_target,
    $puppetdb_database_replica_target,
  ]))

  # Deploy an environment if a deploy environment is specified
  if $deploy_environment {
    run_task('pe_xl::code_manager', $master_target,
      action => "deploy ${deploy_environment}",
    )
  }

  return("Configuration of Puppet Enterprise ${arch['architecture']} succeeded.")
}
