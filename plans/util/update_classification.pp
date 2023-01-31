# @api private
#
# @summary Configure classification
#
plan peadm::util::update_classification (
  # Standard
  Peadm::SingleTargetSpec           $targets,
  Optional[Hash]                    $peadm_config = undef,
  Optional[Peadm::SingleTargetSpec] $server_a_host = undef,
  Optional[Peadm::SingleTargetSpec] $server_b_host = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $postgresql_a_host = undef,
  Optional[Peadm::SingleTargetSpec] $postgresql_b_host = undef,

  # Common Configuration
  Optional[String] $compiler_pool_address = undef,
  Optional[String] $internal_compiler_a_pool_address = undef,
  Optional[String] $internal_compiler_b_pool_address = undef,
) {
  $primary_target = peadm::get_targets($targets, 1)

  # Makes this more easily usable outside a plan
  if $peadm_config {
    $current = $peadm_config
  } else {
    $current = run_task('peadm::get_peadm_config', $primary_target).first.value
  }

  out::verbose('Current config is...')
  out::verbose($current)

  $filtered_params = {
    'compiler_pool_address'            => $compiler_pool_address,
    'internal_compiler_a_pool_address' => $internal_compiler_a_pool_address,
    'internal_compiler_b_pool_address' => $internal_compiler_b_pool_address,
  }.filter |$parameter| { $parameter[1] }

  $filtered_server = {
    'A' => $server_a_host,
    'B' => $server_b_host,
  }.filter |$parameter| { $parameter[1] }

  $filtered_psql = {
    'A' => $postgresql_a_host,
    'B' => $postgresql_b_host,
  }.filter |$parameter| { $parameter[1] }

  $filtered = {
    'params'      => $filtered_params,
    'role-letter' => {
      'server'     => $filtered_server,
      'postgresql' => $filtered_psql,
    },
  }

  out::verbose('New values are...')
  out::verbose($filtered)

  $new = deep_merge($current, $filtered)

  out::verbose('Updating classification to...')
  out::verbose($new)

  apply($primary_target) {
    class { 'peadm::setup::node_manager_yaml':
      primary_host => $primary_target.peadm::certname(),
    }

    class { 'peadm::setup::node_manager':
      primary_host                     => $primary_target.peadm::certname(),
      server_a_host                    => $new['role-letter']['server']['A'],
      server_b_host                    => $new['role-letter']['server']['B'],
      postgresql_a_host                => $new['role-letter']['postgresql']['A'],
      postgresql_b_host                => $new['role-letter']['postgresql']['B'],
      compiler_pool_address            => $new['params']['compiler_pool_address'],
      internal_compiler_a_pool_address => $new['params']['internal_compiler_a_pool_address'],
      internal_compiler_b_pool_address => $new['params']['internal_compiler_b_pool_address'],
      require                          => Class['peadm::setup::node_manager_yaml'],
    }
  }
  return('The classification of Puppet Enterprise components has succeeded.')
}
