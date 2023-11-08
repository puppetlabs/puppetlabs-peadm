plan peadm::add_database(
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $primary_host,
  Optional[Enum['init', 'pair']] $mode = undef,
  Optional[Enum[
      'init-db-node',
      'replicate-db',
      'update-classification',
      'update-db-settings',
      'cleanup-db',
  'finalize']] $begin_at_step = undef,
) {
  $primary_target = peadm::get_targets($primary_host, 1)
  $postgresql_target = peadm::get_targets($targets, 1)

  $postgresql_host = $postgresql_target.peadm::certname()

  # Get current peadm config before making modifications and shutting down
  # PuppetDB
  $peadm_config = run_task('peadm::get_peadm_config', $primary_target).first.value

  $compilers = $peadm_config['params']['compilers']

  # Bail if this is trying to be ran against Standard
  if $compilers.empty {
    fail_plan('Plan peadm::add_database is only applicable for L and XL deployments')
  }

  # Existing nodes and their assignments
  $replica_host = $peadm_config['params']['replica_host']
  $postgresql_a_host = $peadm_config['role-letter']['postgresql']['A']
  $postgresql_b_host = $peadm_config['role-letter']['postgresql']['B']

  $replica_target = peadm::get_targets($replica_host, 1)

  # Pluck these out for determining group letter assignments
  $roles = $peadm_config['role-letter']

  # Override mode in case of failure on previous run
  if $mode {
    $operating_mode = $mode
    out::message("Operating mode overridden by parameter mode set to ${mode}")
  } else {
    # If array is empty then no external databases were previously configured 
    $no_external_db = peadm::flatten_compact([
        $postgresql_a_host,
        $postgresql_b_host,
    ]).empty

    # Pick operating mode based on array check
    if $no_external_db {
      $operating_mode = 'init'
    } else {
      $operating_mode = 'pair'
    }
  }
  out::message("Operating in ${operating_mode} mode")

  if $operating_mode == 'init' {
    # If no other PSQL node then match primary group letter
    $avail_group_letter = peadm::flatten_compact($roles['server'].map |$k,$v| {
        if $v == $primary_host {
          $k
        }
    })[0]
    # Assume PuppetDB backend hosted on Primary if in init mode
    $source_db_host = $primary_host
  } else {
    # The letter which doesn't yet have a server assigned or in the event this
    # is a replacement operation, the letter this node was assigned to previously
    $avail_group_letter = peadm::flatten_compact($roles['postgresql'].map |$k,$v| {
        if (! $v) or ($v == $postgresql_host) {
          $k
        }
    })[0]
    # When in pair mode we assume the other PSQL node will serve as our source
    $source_db_host = peadm::flatten_compact([
        $postgresql_a_host,
        $postgresql_b_host,
    ]).reject($postgresql_host)[0]
  }

  out::message("Adding PostgreSQL server ${postgresql_host} to availability group ${avail_group_letter}")
  out::message("Using ${source_db_host} to populate ${postgresql_host}")

  $source_db_target = peadm::get_targets($source_db_host, 1)

  peadm::plan_step('init-db-node') || {
    # Install PSQL on new node to be used as external PuppetDB backend by using
    # puppet in lieu of installer 
    run_plan('peadm::subplans::component_install', $postgresql_target,
      primary_host       => $primary_target,
      avail_group_letter => $avail_group_letter,
      role               => 'puppet/puppetdb-database'
    )
  }

  # Stop Puppet to ensure catalogs are not being compiled for PE infrastructure nodes
  run_command('systemctl stop puppet.service', peadm::flatten_compact([
        $postgresql_target,
        $compilers,
        $primary_target,
        $replica_target,
        $source_db_target,
  ]))

  # Stop frontend compiler services that causes changes to PuppetDB backend when
  # agents request catalogs
  run_command('systemctl stop pe-puppetserver.service pe-puppetdb.service', $compilers)

  peadm::plan_step('replicate-db') || {
    # Replicate content from source to newly installed PSQL server
    run_plan('peadm::subplans::db_populate', $postgresql_target, source_host => $source_db_target.peadm::certname())

    # Run Puppet on new PSQL node to fix up certificates and permissions
    run_task('peadm::puppet_runonce', $postgresql_target)
  }

  # Update classification and database.ini settings, assume a replica PSQL
  # does not exist
  peadm::plan_step('update-classification') || {
    # To ensure everything is functional when a replica exists but only a single
    # PostgreSQL node has been deployed, configure alternate availability group
    # to connect to other group's new node
    if ($operating_mode == 'init' and $replica_host) {
      $a_host = $avail_group_letter ? { 'A' => $postgresql_host, default => undef }
      $b_host = $avail_group_letter ? { 'B' => $postgresql_host, default => undef }
      $host = pick($a_host, $b_host)
      out::verbose("In transitive state, setting classification to ${host}")
      run_plan('peadm::util::update_classification', $primary_target,
        postgresql_a_host => $host,
        postgresql_b_host => $host,
        peadm_config      => $peadm_config
      )
    } else {
      run_plan('peadm::util::update_classification', $primary_target,
        postgresql_a_host => $avail_group_letter ? { 'A' => $postgresql_host, default => undef },
        postgresql_b_host => $avail_group_letter ? { 'B' => $postgresql_host, default => undef },
        peadm_config      => $peadm_config
      )
    }
  }

  peadm::plan_step('update-db-settings') || {
    run_plan('peadm::util::update_db_setting', peadm::flatten_compact([
          $compilers,
          $primary_target,
          $replica_target,
      ]),
      postgresql_host => $postgresql_host,
      peadm_config    => $peadm_config
    )

    # (Re-)Start PuppetDB now that we are done making modifications
    run_command('systemctl restart pe-puppetdb.service', peadm::flatten_compact([
          $primary_target,
          $replica_target,
    ]))
  }

  peadm::plan_step('cleanup-db') || {
    if $operating_mode == 'init' {
      # Clean up old puppetdb database on primary and those which were copied to
      # new host.
      $target_db_purge = [
        'pe-activity',
        'pe-classifier',
        'pe-inventory',
        'pe-orchestrator',
        'pe-rbac',
      ]

      # If a primary replica exists then pglogical is enabled and will prevent
      # the clean up of databases on our target because it opens a connection. 
      if $replica_host {
        run_plan('peadm::util::db_disable_pglogical', $postgresql_target, databases => $target_db_purge)
      }

      # Clean up old databases
      $clean_source = peadm::flatten_compact([
          $source_db_target,
          $primary_target,
          $replica_target,
      ])

      run_plan('peadm::util::db_purge', $clean_source,      databases => ['pe-puppetdb'])
      run_plan('peadm::util::db_purge', $postgresql_target, databases => $target_db_purge)
    } else {
      out::message("No databases to cleanup when in ${operating_mode}")
    }
  }

  # The pe.conf file needs to be in place or future upgrades will fail.
  $pe_conf = peadm::generate_pe_conf({
      'console_admin_password'                => 'not used',
      'puppet_enterprise::puppet_master_host' => $primary_host.peadm::certname(),
      'puppet_enterprise::database_host'      => $postgresql_target.peadm::certname(),
  })

  run_task('peadm::mkdir_p_file', $postgresql_target,
    path    => '/etc/puppetlabs/enterprise/conf.d/pe.conf',
    content => stdlib::to_json_pretty($pe_conf.parsejson()),
  )

  # Start frontend compiler services so catalogs can once again be compiled by
  # agents
  run_command('systemctl start pe-puppetserver.service pe-puppetdb.service', $compilers)

  peadm::plan_step('finalize') || {
    # Run Puppet to sweep up but no restarts should occur so do them in parallel
    run_task('peadm::puppet_runonce', peadm::flatten_compact([
          $postgresql_target,
          $primary_target,
          $compilers,
          $replica_target,
    ]))

    # Start Puppet agent
    run_command('systemctl start puppet.service', peadm::flatten_compact([
          $postgresql_target,
          $compilers,
          $primary_target,
          $replica_target,
          $source_db_target,
    ]))
  }
}
