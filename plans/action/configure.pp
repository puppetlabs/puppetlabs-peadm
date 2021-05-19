# @summary Configure first-time classification and HA setup
#
# @param compiler_pool_address 
#   The service address used by agents to connect to compilers, or the Puppet
#   service. Typically this is a load balancer.
# @param internal_compiler_a_pool_address
#   A load balancer address directing traffic to any of the "A" pool
#   compilers. This is used for DR/HA configuration in large and extra large
#   architectures.
# @param internal_compiler_b_pool_address
#   A load balancer address directing traffic to any of the "B" pool
#   compilers. This is used for DR/HA configuration in large and extra large
#   architectures.
#
plan peadm::action::configure (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  Optional[Peadm::SingleTargetSpec] $primary_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String           $compiler_pool_address = $primary_host,
  Optional[String] $internal_compiler_a_pool_address = undef,
  Optional[String] $internal_compiler_b_pool_address = undef,
  Optional[String] $token_file = undef,
  Optional[String] $deploy_environment = undef,

  # Other
  String           $stagingdir = '/tmp',
) {
  # TODO: get and validate PE version

  # Convert inputs into targets.
  $primary_target                   = peadm::get_targets($primary_host, 1)
  $primary_replica_target           = peadm::get_targets($primary_replica_host, 1)
  $puppetdb_database_replica_target = peadm::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)
  $puppetdb_database_target         = peadm::get_targets($puppetdb_database_host, 1)

  # Ensure input valid for a supported architecture
  $arch = peadm::validate_architecture(
    $primary_host,
    $primary_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  # Define the global hiera.yaml file on the Master; and syncronize to any Replica and Compilers.
  # This enables Data in the Classifier/Console, which is used/required by this architecture.
  # Necessary, for example, when promoting the Replica due to PE-18400 (and others).
  $global_hiera_yaml = run_task('peadm::read_file', $primary_target,
    path => '/etc/puppetlabs/puppet/hiera.yaml',
  ).first['content']

  run_task('peadm::mkdir_p_file', peadm::flatten_compact([
    $primary_replica_target,
    $compiler_targets,
  ]),
    path    => '/etc/puppetlabs/puppet/hiera.yaml',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $global_hiera_yaml,
  )

  # Set up the console node groups to configure the various hosts in their roles

  apply($primary_target) {
    class { 'peadm::setup::node_manager_yaml':
      primary_host => $primary_target.peadm::target_name(),
    }

    class { 'peadm::setup::node_manager':
      primary_host                     => $primary_target.peadm::target_name(),
      primary_replica_host             => $primary_replica_target.peadm::target_name(),
      puppetdb_database_host           => $puppetdb_database_target.peadm::target_name(),
      puppetdb_database_replica_host   => $puppetdb_database_replica_target.peadm::target_name(),
      compiler_pool_address            => $compiler_pool_address,
      internal_compiler_a_pool_address => $internal_compiler_a_pool_address,
      internal_compiler_b_pool_address => $internal_compiler_b_pool_address,
      require                          => Class['peadm::setup::node_manager_yaml'],
    }
  }

  if $arch['high-availability'] {
    # Run the PE Replica Provision
    run_task('peadm::provision_replica', $primary_target,
      master_replica => $primary_replica_target.peadm::target_name(),
      token_file     => $token_file,

      # Race condition, where the provision command checks PuppetDB status and
      # probably gets "starting", but fails out because that's not "running".
      # Can remove flag when that issue is fixed.
      legacy         => true,
    )
  }

  # Run Puppet everywhere to pick up last remaining config tweaks
  run_task('peadm::puppet_runonce', peadm::flatten_compact([
    $primary_target,
    $puppetdb_database_target,
    $compiler_targets,
    $primary_replica_target,
    $puppetdb_database_replica_target,
  ]))

  # Deploy an environment if a deploy environment is specified
  if $deploy_environment {
    run_task('peadm::code_manager', $primary_target,
      action => "deploy ${deploy_environment}",
    )
  }

  # Ensure Puppet agent service is running now that configuration is complete
  run_command('systemctl start puppet', peadm::flatten_compact([
    $primary_target,
    $primary_replica_target,
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
    $compiler_targets,
  ]))

  return("Configuration of Puppet Enterprise ${arch['architecture']} succeeded.")
}
