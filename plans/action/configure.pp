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
  # TODO: get and validate PE version

  # Convert inputs into targets.
  $master_target                    = peadm::get_targets($master_host, 1)
  $master_replica_target            = peadm::get_targets($master_replica_host, 1)
  $puppetdb_database_replica_target = peadm::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)
  $puppetdb_database_target         = peadm::get_targets($puppetdb_database_host, 1)

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

  apply($master_target) {
    class { 'peadm::setup::node_manager_yaml':
      master_host => $master_target.peadm::target_name(),
    }

    class { 'peadm::setup::node_manager':
      master_host                    => $master_target.peadm::target_name(),
      master_replica_host            => $master_replica_target.peadm::target_name(),
      puppetdb_database_host         => $puppetdb_database_target.peadm::target_name(),
      puppetdb_database_replica_host => $puppetdb_database_replica_target.peadm::target_name(),
      compiler_pool_address          => $compiler_pool_address,
      require                        => Class['peadm::setup::node_manager_yaml'],
    }
  }

  if $arch['high-availability'] {
    # Run the PE Replica Provision
    run_task('peadm::provision_replica', $master_target,
      master_replica => $master_replica_target.peadm::target_name(),
      token_file     => $token_file,

      # Race condition, where the provision command checks PuppetDB status and
      # probably gets "starting", but fails out because that's not "running".
      # Can remove flag when that issue is fixed.
      legacy         => true,
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
