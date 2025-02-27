plan peadm_spec::test_migration(
  String $primary_host,
  String $new_primary_host,
  Optional[String] $new_replica_host = undef,
  Optional[String] $upgrade_version = undef,
) {
  out::message("primary_host:${primary_host}.")
  out::message("new_primary_host:${new_primary_host}.")
  out::message("new_replica_host:${new_replica_host}.")
  out::message("upgrade_version:${upgrade_version}.")

  # Convert String values to targets if they are not blank
  $primary_target = $primary_host ? { '' => undef, default => peadm::get_targets($primary_host, 1) }
  $new_primary_target = $new_primary_host ? { '' => undef, default => peadm::get_targets($new_primary_host, 1) }
  $new_replica_target = $new_replica_host ? { '' => undef, default => peadm::get_targets($new_replica_host, 1) }

  # output the targets
  out::message("primary_target:${primary_target}.")
  out::message("new_primary_target:${new_primary_target}.")
  out::message("new_replica_target:${new_replica_target}.")

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
    upgrade_version  => $upgrade_version,
    replica_host     => $new_replica_target,
  )
}
