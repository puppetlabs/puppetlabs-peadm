# @api private
plan peadm::convert_compiler_to_legacy (
  Peadm::SingleTargetSpec $primary_host,
  TargetSpec $legacy_hosts,
  Boolean $remove_pdb = false,
) {
  $primary_target            = peadm::get_targets($primary_host, 1)
  $legacy_compiler_targets             = peadm::get_targets($legacy_hosts)

  $cluster = run_task('peadm::get_peadm_config', $primary_host).first.value
  $error = getvar('cluster.error')
  if $error {
    fail_plan($error)
  }

  $all_targets = peadm::flatten_compact([
      getvar('cluster.params.primary_host'),
      getvar('cluster.params.replica_host'),
      getvar('cluster.params.primary_postgresql_host'),
      getvar('cluster.params.replica_postgresql_host'),
      getvar('cluster.params.compiler_hosts'),
  ])

  if $remove_pdb {
    run_command('puppet resource service puppet ensure=stopped', $legacy_compiler_targets)
    run_command('puppet resource service pe-puppetdb ensure=stopped enable=false', $legacy_compiler_targets)
  }

  apply($primary_target) {
    class { 'peadm::setup::node_manager_yaml':
      primary_host => $primary_target.peadm::certname(),
    }

    class { 'peadm::setup::legacy_compiler_group':
      primary_host => $primary_target.peadm::certname(),
    }
  }

  run_plan('peadm::update_compiler_extensions',  compiler_hosts => $legacy_compiler_targets, primary_host => $primary_target, legacy => true)

  run_task('peadm::puppet_runonce', $legacy_compiler_targets)
  run_task('peadm::puppet_runonce', $primary_target)
  run_task('peadm::puppet_runonce', $all_targets)

  if $remove_pdb {
    run_command('puppet resource package pe-puppetdb ensure=purged', $legacy_compiler_targets)
    run_command('puppet resource user pe-puppetdb ensure=absent', $legacy_compiler_targets)

    run_command('rm -rf /etc/puppetlabs/puppetdb', $legacy_compiler_targets)
    run_command('rm -rf /var/log/puppetlabs/puppetdb', $legacy_compiler_targets)
    run_command('rm -rf /opt/puppetlabs/server/data/puppetdb', $legacy_compiler_targets)
  }

  run_command('systemctl start pe-puppetserver.service', $legacy_compiler_targets)
  run_command('puppet resource service puppet ensure=running', $legacy_compiler_targets)

  return("Converted host ${legacy_compiler_targets} to legacy compiler.")
}
