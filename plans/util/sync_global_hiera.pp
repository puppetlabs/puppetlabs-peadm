# @api private
plan peadm::util::sync_global_hiera (
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $primary_host,
) {

  $primary_target             = peadm::get_targets($primary_host, 1)
  $replica_target             = $targets

  # Source the global hiera.yaml from Primary and synchronize to new Replica 
  $global_hiera_yaml = run_task('peadm::read_file', $primary_target,
    path => '/etc/puppetlabs/puppet/hiera.yaml',
  ).first['content']

  run_task('peadm::mkdir_p_file', $replica_target,
    path    => '/etc/puppetlabs/puppet/hiera.yaml',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $global_hiera_yaml,
  )
}
