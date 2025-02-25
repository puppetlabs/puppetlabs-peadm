plan peadm_spec::test_migration(
  Peadm::SingleTargetSpec $primary_host,
  Peadm::SingleTargetSpec $new_primary_host,
  Optional[Peadm::SingleTargetSpec] $new_replica_host = undef,
  Optional[Peadm::SingleTargetSpec] $new_primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $new_replica_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $upgrade_version = undef,
) {
  out::message("primary_host:${primary_host}.")
  out::message("new_primary_host:${new_primary_host}.")
  out::message("new_replica_host:${new_replica_host}.")
  out::message("new_primary_postgresql_host:${new_primary_postgresql_host}.")
  out::message("new_replica_postgresql_host:${new_replica_postgresql_host}.")

  # run infra status on the primary
  out::message("Running peadm::status on primary host ${primary_host}")
  $primary_status = run_plan('peadm::status', $primary_host, { 'format' => 'json' })
  out::message($primary_status)

  if empty($primary_status['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }

  # perform the migration
  run_plan('peadm::migrate',
    old_primary_host => $primary_host,
    new_primary_host => $new_primary_host,
  )

  # run infra status on the new primary
  out::message("Running peadm::status on new primary host ${new_primary_host}")
  $new_primary_status = run_plan('peadm::status', $new_primary_host, { 'format' => 'json' })
  out::message($new_primary_status)

  if empty($new_primary_status['failed']) {
    out::message('Migrated cluster is healthy, continuing')
  } else {
    fail_plan('Migrated cluster is not healthy, aborting')
  }

  # get the config from new_primary_host and verify config looks as expected
  $result = run_task('peadm::get_peadm_config', $new_primary_host, '_catch_errors' => true).first.to_data()
  out::message("peadm_config: ${result}")
  # if new_replica_host is supplied then check that is in the expected place in the config
  if $new_replica_host {
    if $peadm_config['params']['replica_host'] == $new_replica_host {
      out::message("New replica host ${new_replica_host} set up correctly")
    } else {
      fail_plan("New replica host ${new_replica_host} was not set up correctly")
    }
  }

  # if new_primary_postgresql_host is supplied then check that is in the expected place in the config
  if $new_primary_postgresql_host {
    if $peadm_config['params']['primary_postgresql_host'] == $new_primary_postgresql_host {
      out::message("New primary postgres host ${new_primary_postgresql_host} set up correctly")
    } else {
      fail_plan("New primary postgres host ${new_primary_postgresql_host} was not set up correctly")
    }
  }

  # if new_replica_postgresql_host is supplied then check that is in the expected place in the config
  if $new_replica_postgresql_host {
    if $peadm_config['params']['replica_postgresql_host'] == $new_replica_postgresql_host {
      out::message("New primary postgres host ${new_replica_postgresql_host} set up correctly")
    } else {
      fail_plan("New primary postgres host ${new_replica_postgresql_host} was not set up correctly")
    }
  }

  # if a new PE version was specified then check it has been upgraded
  if $upgrade_version {
    if $peadm_config['params']['pe_version'] == $upgrade_version {
      out::message("Upgraded to new PE version ${upgrade_version} correctly")
    } else {
      fail_plan("Failed to upgrade to new PE version ${upgrade_version} correctly")
    }
  }
}
