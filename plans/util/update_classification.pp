# @api private
#
# @summary Configure first-time classification and DR setup
#
# @param compiler_pool_address 
#   The service address used by agents to connect to compilers, or the Puppet
#   service. Typically this is a load balancer.
# @param internal_compiler_a_pool_address
#   A load balancer address directing traffic to any of the "A" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
# @param internal_compiler_b_pool_address
#   A load balancer address directing traffic to any of the "B" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
#
plan peadm::util::update_classification (
  # Standard
  Peadm::SingleTargetSpec           $targets,
  Hash                              $peadm_config,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Common Configuration
  Optional[String] $compiler_pool_address = undef,
  Optional[String] $internal_compiler_a_pool_address = undef,
  Optional[String] $internal_compiler_b_pool_address = undef,
) {

  $current = $peadm_config['params']

  # Convert inputs into targets.
  $primary_target                   = peadm::get_targets($targets, 1)
  $replica_target                   = peadm::get_targets($replica_host, 1)
  $primary_postgresql_target        = peadm::get_targets($primary_postgresql_host, 1)
  $replica_postgresql_target        = peadm::get_targets($replica_postgresql_host, 1)

  if (! $replica_postgresql_target.peadm::certname()) and $current['replica_host'] {
    out::message('Overriding replica_postgresql_target while in transitive state')
    $overridden_replica_postgresql_target = $primary_postgresql_target
  } else {
    $overridden_replica_postgresql_target = $replica_postgresql_target
  }
  out::message("replica_postgresql_host will be set to ${overridden_replica_postgresql_target.peadm::certname()}")

  $new = merge($current, {
    "primary_host" => $primary_target.peadm::certname(),
    "replica_host" => $replica_target.peadm::certname(),
    "primary_postgresql_host" => $primary_postgresql_target.peadm::certname(),
    "replica_postgresql_host" => $overridden_replica_postgresql_target.peadm::certname(),
    "compiler_pool_address" => $compiler_pool_address,
    "internal_compiler_a_pool_address" => $internal_compiler_a_pool_address,
    "internal_compiler_b_pool_address" => $internal_compiler_b_pool_address
  })

  apply($primary_target) {
    class { 'peadm::setup::node_manager_yaml':
      primary_host => $primary_target.peadm::certname(),
    }

    class { 'peadm::setup::node_manager':
      primary_host                     => $new['primary_host'],
      server_a_host                    => $new['primary_host'],
      server_b_host                    => $new['replica_host'],
      postgresql_a_host                => $new['primary_postgresql_host'],
      postgresql_b_host                => $new['replica_postgresql_host'],
      compiler_pool_address            => $new['compiler_pool_address'],
      internal_compiler_a_pool_address => $new['internal_compiler_a_pool_address'],
      internal_compiler_b_pool_address => $new['internal_compiler_b_pool_address'],
      require                          => Class['peadm::setup::node_manager_yaml'],
    }
  }
  return("The classification of Puppet Enterprise components has succeeded.")
}
