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

  # Get current peadm config before making modifications and shutting down
  # PuppetDB
  $peadm_config = run_task('peadm::get_peadm_config', $primary_target).first.value

  $compilers = $peadm_config['params']['compilers']

  # Bail if this is trying to be ran against Standard
  if $compilers.empty {
    fail_plan('Plan Peadm::Add_database only applicable for L and XL deployments')
  }

  # Existing nodes and their assignments
  $replica_host = $peadm_config['params']['replica_host']
  $primary_postgresql_host = $peadm_config['params']['primary_postgresql_host']
  $replica_postgresql_host = $peadm_config['params']['replica_postgresql_host']

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
      $primary_postgresql_host,
      $replica_postgresql_host
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
      if (! $v) or ($v == $targets.peadm::certname()) {
        $k
      }
    })[0]
    # When in pair mode we assume the other PSQL node will serve as our source
    $source_db_host = peadm::flatten_compact([
      $primary_postgresql_host,
      $replica_postgresql_host
    ]).reject($targets.peadm::certname())[0]
  }

  out::message("Adding PostgreSQL server ${targets.peadm::certname()} to availability group ${avail_group_letter}")
  out::message("Using ${source_db_host} to populate ${targets.peadm::certname()}")

  $source_db_target = peadm::get_targets($source_db_host, 1)

  peadm::plan_step('init-db-node') || {
    # Install PSQL on new node to be used as external PuppetDB backend by using
    # puppet in lieu of installer 
    run_plan('peadm::subplans::component_install', $targets,
      primary_host       => $primary_target,
      avail_group_letter => $avail_group_letter,
      role               => 'puppet/puppetdb-database'
    )
  }

  # Stop Puppet to ensure catalogs are not being compiled for PE infrastructure nodes
  run_command('systemctl stop puppet.service', peadm::flatten_compact([
    $targets,
    $compilers,
    $primary_target,
    $replica_target,
    $source_db_target
  ]))

  # Stop frontend compiler services that causes changes to PuppetDB backend when
  # agents request catalogs
  run_command('systemctl stop pe-puppetserver.service pe-puppetdb.service', $compilers)

  peadm::plan_step('replicate-db') || {
    # Replicate content from source to newly installed PSQL server
    run_plan('peadm::subplans::db_populate', $targets, source_host => $source_db_target.peadm::certname())

    # Run Puppet on new PSQL node to fix up certificates and permissions
    run_task('peadm::puppet_runonce', $targets)
  }

  if $operating_mode == 'init' {

    # Update classification and database.ini settings, assume a replica PSQL
    # does not exist
    peadm::plan_step('update-classification') || {
      run_plan('peadm::util::update_classification', $primary_target,
        primary_postgresql_host => pick($primary_postgresql_host, $targets),
        peadm_config            => $peadm_config
      )
    }

    peadm::plan_step('update-db-settings') || {
      run_plan('peadm::util::update_db_setting', peadm::flatten_compact([
        $compilers,
        $primary_target,
        $replica_target
      ]),
        primary_postgresql_host => $targets,
        peadm_config            => $peadm_config
      )

      # (Re-)Start PuppetDB now that we are done making modifications
      run_command('systemctl restart pe-puppetdb.service', peadm::flatten_compact([
        $primary_target,
        $replica_target
      ]))
    }

    # Clean up old puppetdb database on primary and those which were copied to
    # new host.
    peadm::plan_step('cleanup-db') || {

      $target_db_purge = [
        'pe-activity',
        'pe-classifier',
        'pe-inventory',
        'pe-orchestrator',
        'pe-rbac'
      ]

      # If a primary replica exists then pglogical is enabled and will prevent
      # the clean up of databases on our target because it opens a connection. 
      if $replica_host {
        run_plan('peadm::util::db_disable_pglogical', $targets, databases => $target_db_purge)
      }

      # Clean up old databases
      $clean_source = peadm::flatten_compact([
        $source_db_target,
        $primary_target,
        $replica_target
      ])

      run_plan('peadm::util::db_purge', $clean_source, databases => ['pe-puppetdb'])
      run_plan('peadm::util::db_purge', $targets,      databases => $target_db_purge)
    }
  } else {
    peadm::plan_step('update-classification') || {
      run_plan('peadm::util::update_classification', $primary_target,
        primary_postgresql_host => pick($primary_postgresql_host, $targets),
        replica_postgresql_host => pick($replica_postgresql_host, $targets),
        peadm_config            => $peadm_config
      )
    }

    # Plan needs to know which node is being added as well as primary and
    # replica designation
    peadm::plan_step('update-db-settings') || {
      run_plan('peadm::util::update_db_setting', peadm::flatten_compact([
        $compilers,
        $primary_target,
        $replica_target
      ]),
        new_postgresql_host     => $targets,
        primary_postgresql_host => pick($primary_postgresql_host, $targets),
        replica_postgresql_host => pick($replica_postgresql_host, $targets),
        peadm_config            => $peadm_config
      )

      # (Re-)Start PuppetDB now that we are done making modifications
      run_command('systemctl restart pe-puppetdb.service', peadm::flatten_compact([
        $primary_target,
        $replica_target
      ]))
    }
    peadm::plan_step('cleanup-db') || {
      out::message("No databases to cleanup when in ${operating_mode}")
    }
  }

  # Start frontend compiler services so catalogs can once again be compiled by
  # agents
  run_command('systemctl start pe-puppetserver.service pe-puppetdb.service', $compilers)


  peadm::plan_step('finalize') || {
    # Run Puppet to sweep up but no restarts should occur so do them in parallel
    run_task('peadm::puppet_runonce', peadm::flatten_compact([
      $targets,
      $primary_target,
      $compilers,
      $replica_target
    ]))

    # Start Puppet agent
    run_command('systemctl start puppet.service', peadm::flatten_compact([
      $targets,
      $compilers,
      $primary_target,
      $replica_target,
      $source_db_target
    ]))
  }
}
