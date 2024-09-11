# @api private
plan peadm::convert_compiler_to_legacy (
  Peadm::SingleTargetSpec $primary_host,
  TargetSpec $legacy_hosts,
  Boolean $remove_pdb = true,
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

  # Ensure input valid for a supported architecture
  $arch = peadm::assert_supported_architecture(
    getvar('cluster.params.primary_host'),
    getvar('cluster.params.replica_host'),
    getvar('cluster.params.primary_postgresql_host'),
    getvar('cluster.params.replica_postgresql_host'),
    getvar('cluster.params.compiler_hosts'),
  )

  if $arch['disaster-recovery'] {
    $legacy_compiler_a_targets = $legacy_compiler_targets.filter |$index,$target| {
      $exts = $cert_extensions[$target.peadm::certname()]
      if ($exts[peadm::oid('peadm_availability_group')] in ['A', 'B']) {
        $exts[peadm::oid('peadm_availability_group')] == 'A'
      }
      elsif ($exts[peadm::oid('pp_cluster')] in ['A', 'B']) {
        $exts[peadm::oid('pp_cluster')] == 'A'
      }
      else {
        $index % 2 == 0
      }
    }
    $legacy_compiler_b_targets = $legacy_compiler_targets.filter |$index,$target| {
      $exts = $cert_extensions[$target.peadm::certname()]
      if ($exts[peadm::oid('peadm_availability_group')] in ['A', 'B']) {
        $exts[peadm::oid('peadm_availability_group')] == 'B'
      }
      elsif ($exts[peadm::oid('pp_cluster')] in ['A', 'B']) {
        $exts[peadm::oid('pp_cluster')] == 'B'
      }
      else {
        $index % 2 != 0
      }
    }
  } else {
    $legacy_compiler_a_targets = $legacy_compiler_targets
    $legacy_compiler_b_targets = []
  }

  $compiler_targets = peadm::flatten_compact([getvar('cluster.params.compiler_hosts')])

  wait([
      background('modify-compilers-certs') || {
        run_plan('peadm::modify_certificate', $compiler_targets,
          primary_host   => $primary_target,
          add_extensions => {
            peadm::oid('peadm_legacy_compiler')    => 'false',
          },
        )
      },
      background('modify-compilers-a-certs') || {
        run_plan('peadm::modify_certificate', $legacy_compiler_a_targets,
          primary_host   => $primary_target,
          add_extensions => {
            peadm::oid('pp_auth_role')             => 'pe_compiler',
            peadm::oid('peadm_availability_group') => 'A',
            peadm::oid('peadm_legacy_compiler')    => 'true',
          },
        )
      },
      background('modify-compilers-b-certs') || {
        run_plan('peadm::modify_certificate', $legacy_compiler_b_targets,
          primary_host   => $primary_target,
          add_extensions => {
            peadm::oid('pp_auth_role')             => 'pe_compiler',
            peadm::oid('peadm_availability_group') => 'B',
            peadm::oid('peadm_legacy_compiler')    => 'true',
          },
        )
      },
  ])

  if $remove_pdb {
    run_command('puppet resource service puppet ensure=stopped', $legacy_compiler_targets)
    run_command('puppet resource service pe-puppetdb ensure=stopped enable=false', $legacy_compiler_targets)
  }

  apply($primary_target) {
    class { 'peadm::setup::node_manager_yaml':
      primary_host => $primary_target.peadm::certname(),
    },

    class { 'peadm::setup::legacy_compiler_group':
      primary_host                     => $primary_target.peadm::certname(),
      internal_compiler_a_pool_address => $cluster['params']['internal_compiler_a_pool_address'],
      internal_compiler_b_pool_address => $cluster['params']['internal_compiler_b_pool_address'],
      require                          => Class['peadm::setup::node_manager_yaml'],
    }
  }

  run_task('peadm::puppet_runonce', $legacy_compiler_targets)
  run_task('peadm::puppet_runonce', $compiler_targets)
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
