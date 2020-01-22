# @summary Configure first-time classification and HA setup
#
plan peadm::action::configure (
  # Standard
  Peadm::SingleTargetSpec           $master_host,
  Optional[Peadm::SingleTargetSpec] $master_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String           $compiler_pool_address = $master_host,
  Optional[String] $token_file = undef,
  Optional[String] $deploy_environment = undef,

  # Other
  String           $stagingdir = '/tmp',
) {
  # Convert inputs into targets.
  $master_target                    = peadm::get_targets($master_host, 1)
  $master_replica_target            = peadm::get_targets($master_replica_host, 1)
  $puppetdb_database_replica_target = peadm::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)
  $puppetdb_database_target         = $puppetdb_database_host ? {
    undef   => $master_target,
    default => peadm::get_targets($puppetdb_database_host, 1)
  }

  # Ensure input valid for a supported architecture
  $arch = peadm::validate_architecture(
    $master_host,
    $master_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  # Define the global hiera.yaml file on the Master; and syncronize to any Replica and Compilers.
  # This enables Data in the Classifier/Console, which is used/required by this architecture.
  # Necessary, for example, when promoting the Replica due to PE-18400 (and others).
  $global_hiera_yaml = run_task('peadm::read_file', $master_target,
    path => '/etc/puppetlabs/puppet/hiera.yaml',
  ).first['content']

  run_task('peadm::mkdir_p_file', peadm::flatten_compact([
    $master_replica_target,
    $compiler_targets,
  ]),
    path    => '/etc/puppetlabs/puppet/hiera.yaml',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $global_hiera_yaml,
  )

  # Set up the console node groups to configure the various hosts in their roles

  # Pending resolution of Bolt GH-1244, Target objects and their methods are
  # not accessible inside apply() blocks. Work around the limitation for now
  # by using string variables calculated outside the apply block. The
  # commented-out values should be used once GH-1244 is resolved.

  # WORKAROUND: GH-1244
  $master_host_string = $master_target.peadm::target_name()
  $master_replica_host_string = $master_replica_target.peadm::target_name()
  $puppetdb_database_host_string = $puppetdb_database_target.peadm::target_name()
  $puppetdb_database_replica_host_string = $puppetdb_database_replica_target.peadm::target_name()

  apply($master_target) {
    # Necessary to give the sandboxed Puppet executor the configuration
    # necessary to connect to the classifier`
    file { 'node_manager.yaml':
      ensure  => file,
      mode    => '0644',
      path    => Deferred('peadm::node_manager_yaml_location'),
      content => epp('peadm/node_manager.yaml.epp', {
        server => $master_host_string,
      }),
    }

    class { 'peadm::setup::node_manager':
      # WORKAROUND: GH-1244
      master_host                    => $master_host_string, # $master_target.peadm::target_name(),
      master_replica_host            => $master_replica_host_string, # $master_replica_target.peadm::target_name(),
      puppetdb_database_host         => $puppetdb_database_host_string, # $puppetdb_database_target.peadm::target_name(),
      puppetdb_database_replica_host => $puppetdb_database_replica_host_string, # $puppetdb_database_replica_target.peadm::target_name(),
      compiler_pool_address          => $compiler_pool_address,
      require                        => File['node_manager.yaml'],
    }
  }

  # Run Puppet in no-op on the compilers so that their status in PuppetDB
  # is updated and they can be identified by the puppet_enterprise module as
  # CMs
  run_task('peadm::puppet_runonce', peadm::flatten_compact([
    $compiler_targets,
    $master_replica_target,
  ]),
    noop => true,
  )

  # Run Puppet on the PuppetDB Database hosts to update their auth
  # configuration to allow the compilers to connect
  run_task('peadm::puppet_runonce', peadm::flatten_compact([
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
  ]))

  # Run Puppet on the master to ensure all services configured and
  # running in prep for provisioning the replica. This is done separately so
  # that a service restart of pe-puppetserver doesn't cause Puppet runs on
  # other nodes to fail.
  run_task('peadm::puppet_runonce', $master_target)

  if $arch['high-availability'] {
    # Run the PE Replica Provision
    run_task('peadm::provision_replica', $master_target,
      master_replica => $master_replica_target.peadm::target_name(),
      token_file     => $token_file,
    )

    # Run the PE Replica Enable
    run_task('peadm::enable_replica', $master_target,
      master_replica => $master_replica_target.peadm::target_name(),
      token_file     => $token_file,
    )
  }

  # Run Puppet everywhere to pick up last remaining config tweaks
  run_task('peadm::puppet_runonce', peadm::flatten_compact([
    $master_target,
    $puppetdb_database_target,
    $compiler_targets,
    $master_replica_target,
    $puppetdb_database_replica_target,
  ]))

  # Deploy an environment if a deploy environment is specified
  if $deploy_environment {
    run_task('peadm::code_manager', $master_target,
      action => "deploy ${deploy_environment}",
    )
  }

  # Ensure Puppet agent service is running now that configuration is complete
  run_command('systemctl start puppet', peadm::flatten_compact([
    $master_target,
    $master_replica_target,
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
    $compiler_targets,
  ]))

  return("Configuration of Puppet Enterprise ${arch['architecture']} succeeded.")
}
