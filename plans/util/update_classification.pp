# @api private
#
# @summary Configure classification
#
plan peadm::util::update_classification (
  # Standard
  Peadm::SingleTargetSpec           $targets,
  Optional[Hash]                    $peadm_config = undef,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Common Configuration
  Optional[String] $compiler_pool_address = undef,
  Optional[String] $internal_compiler_a_pool_address = undef,
  Optional[String] $internal_compiler_b_pool_address = undef,
) {

  # Convert inputs into targets.
  $primary_target                   = peadm::get_targets($targets, 1)
  $replica_target                   = peadm::get_targets($replica_host, 1)
  $primary_postgresql_target        = peadm::get_targets($primary_postgresql_host, 1)
  $replica_postgresql_target        = peadm::get_targets($replica_postgresql_host, 1)

  # Makes this more easily usable outside a plan
  if $peadm_config {
    $current = $peadm_config['params']
  } else {
    $current = run_task('peadm::get_peadm_config', $primary_target).first.value['params']
  }

  # When a replica in configured, the B side of the deployment requires that
  # replica_postgresql_host to be set, if it is not then PuppetDB will be left
  # non-functional. Doing this will allow both sides of the deployment to start
  # up and be functional until the second PostgreSQL node can be provisioned and configured.
  if (! $replica_postgresql_target.peadm::certname()) and $current['replica_host'] {
    out::message('Overriding replica_postgresql_host while in transitive state')
    $overridden_replica_postgresql_target = $primary_postgresql_target
  } else {
    $overridden_replica_postgresql_target = $replica_postgresql_target
  }

  $new = merge($current, {
    'primary_host' => $primary_target.peadm::certname(),
    'replica_host' => $replica_target.peadm::certname(),
    'primary_postgresql_host' => $primary_postgresql_target.peadm::certname(),
    'replica_postgresql_host' => $overridden_replica_postgresql_target.peadm::certname(),
    'compiler_pool_address' => $compiler_pool_address,
    'internal_compiler_a_pool_address' => $internal_compiler_a_pool_address,
    'internal_compiler_b_pool_address' => $internal_compiler_b_pool_address
  })

  out::message('Classification to be updated using the following hash...')
  out::message($new)

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
  return('The classification of Puppet Enterprise components has succeeded.')
}
