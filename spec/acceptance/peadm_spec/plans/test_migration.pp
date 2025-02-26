plan peadm_spec::test_migration(
  String $primary_host,
  String $new_primary_host,
  Optional[String] $new_replica_host = undef,
  Optional[String] $new_primary_postgresql_host = undef,
  Optional[String] $new_replica_postgresql_host = undef,
  Optional[String] $upgrade_version = undef,
) {
  out::message("primary_host:${primary_host}.")
  out::message("new_primary_host:${new_primary_host}.")
  out::message("new_replica_host:${new_replica_host}.")
  out::message("new_primary_postgresql_host:${new_primary_postgresql_host}.")
  out::message("new_replica_postgresql_host:${new_replica_postgresql_host}.")
  out::message("upgrade_version:${upgrade_version}.")

  # Convert String values to targets if they are not blank
  $primary_target = $primary_host ? { '' => undef, default => peadm::get_targets($primary_host, 1) }
  $new_primary_target = $new_primary_host ? { '' => undef, default => peadm::get_targets($new_primary_host, 1) }
  $new_replica_target = $new_replica_host ? { '' => undef, default => peadm::get_targets($new_replica_host, 1) }
  $new_primary_postgresql_target = $new_primary_postgresql_host ? { '' => undef, default => peadm::get_targets($new_primary_postgresql_host, 1) }
  $new_replica_postgresql_target = $new_replica_postgresql_host ? { '' => undef, default => peadm::get_targets($new_replica_postgresql_host, 1) }

  # output the targets
  out::message("primary_target:${primary_target}.")
  out::message("new_primary_target:${new_primary_target}.")
  out::message("new_replica_target:${new_replica_target}.")
  out::message("new_primary_postgresql_target:${new_primary_postgresql_target}.")
  out::message("new_replica_postgresql_target:${new_replica_postgresql_target}.")

  # run infra status on the primary
  out::message("Running peadm::status on primary host ${primary_target}")
  $primary_status = run_plan('peadm::status', $primary_target, { 'format' => 'json' })
  out::message($primary_status)

  if empty($primary_status['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }

  # perform the migration
  run_plan('peadm::migrate',
    old_primary_host => $primary_target,
    new_primary_host => $new_primary_target,
  )

  # run infra status on the new primary
  out::message("Running peadm::status on new primary host ${new_primary_target}")
  $new_primary_status = run_plan('peadm::status', $new_primary_target, { 'format' => 'json' })
  out::message($new_primary_status)

  if empty($new_primary_status['failed']) {
    out::message('Migrated cluster is healthy, continuing')
  } else {
    fail_plan('Migrated cluster is not healthy, aborting')
  }

  # get the config from new_primary_target and verify config looks as expected
  $peadm_config = run_task('peadm::get_peadm_config', $new_primary_target, '_catch_errors' => true).first.to_data()
  out::message("peadm_config: ${peadm_config}")
  # if new_replica_target is supplied then check that is in the expected place in the config
  if $new_replica_target {
    if $peadm_config['params']['replica_host'] == $new_replica_target {
      out::message("New replica host ${new_replica_target} set up correctly")
    } else {
      fail_plan("New replica host ${new_replica_target} was not set up correctly")
    }
  }

  # if new_primary_postgresql_target is supplied then check that is in the expected place in the config
  if $new_primary_postgresql_target {
    if $peadm_config['params']['primary_postgresql_host'] == $new_primary_postgresql_target {
      out::message("New primary postgres host ${new_primary_postgresql_target} set up correctly")
    } else {
      fail_plan("New primary postgres host ${new_primary_postgresql_target} was not set up correctly")
    }
  }

  # if new_replica_postgresql_target is supplied then check that is in the expected place in the config
  if $new_replica_postgresql_target {
    if $peadm_config['params']['replica_postgresql_host'] == $new_replica_postgresql_target {
      out::message("New primary postgres host ${new_replica_postgresql_target} set up correctly")
    } else {
      fail_plan("New primary postgres host ${new_replica_postgresql_target} was not set up correctly")
    }
  }

  # if a new PE version was specified then check it has been upgraded
  if $upgrade_version and $upgrade_version != '' {
    if $peadm_config['value']['pe_version'] == $upgrade_version {
      out::message("Upgraded to new PE version ${upgrade_version} correctly")
    } else {
      fail_plan("Failed to upgrade to new PE version ${upgrade_version} correctly")
    }
  }
}
