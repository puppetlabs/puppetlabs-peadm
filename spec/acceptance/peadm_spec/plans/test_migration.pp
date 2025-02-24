plan peadm_spec::test_migration(
  Peadm::SingleTargetSpec   $primary_host,
  Peadm::SingleTargetSpec   $replica_host,
  Peadm::SingleTargetSpec   $primary_postgresql_host,
  Peadm::SingleTargetSpec   $replica_postgresql_host,
  Peadm::SingleTargetSpec   $new_primary_host,
  Peadm::SingleTargetSpec   $new_replica_host,
  Peadm::SingleTargetSpec   $new_primary_postgresql_host,
  Peadm::SingleTargetSpec   $new_replica_postgresql_host,
) {
  out::message("primary_host:${primary_host}.")
  out::message("replica_host:${replica_host}.")
  out::message("primary_postgresql_host:${primary_postgresql_host}.")
  out::message("replica_postgresql_host:${replica_postgresql_host}.")
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

  # # perform the migration
  # run_plan('peadm::migrate',
  #   old_primary_host => $primary_host,
  #   new_primary_host => $new_primary_host,
  # )

  # # run infra status on the new primary
  # out::message("Running peadm::status on new primary host ${new_primary_host}")
  # $new_primary_status = run_plan('peadm::status', $new_primary_host, { 'format' => 'json' })
  # out::message($primary_status)

  # if empty($new_primary_status['failed']) {
  #   out::message('Migrated cluster is healthy, continuing')
  # } else {
  #   fail_plan('Migrated cluster is not healthy, aborting')
  # }

  # MIGHT WANT TO ADD CHECKS HERE TO VERIFY THE NEW ARCHITECTURE IS AS EXPECTED

  # # get the config from primary_host and verify failed_postgresql_host is removed and replacement was added
  # $result = run_task('peadm::get_peadm_config', $primary_host, '_catch_errors' => true).first.to_data()
  # $primary_postgres_host = $result['value']['params']['primary_postgresql_host']
  # $replica_postgres_host = $result['value']['params']['replica_postgresql_host']

  # if $primary_postgres_host == $failed_postgresql_host or $replica_postgres_host == $failed_postgresql_host {
  #   fail_plan("Failed PostgreSQL host ${failed_postgresql_host} was not removed from the PE configuration")
  # } else {
  #   out::message("Failed PostgreSQL host ${failed_postgresql_host} was removed from the PE configuration")
  # }
  # if $primary_postgres_host == $replacement_postgresql_host or $replica_postgres_host == $replacement_postgresql_host {
  #   out::message("Replacement PostgreSQL host ${replacement_postgresql_host} was added to the PE configuration")
  # } else {
  #   fail_plan("Replacement PostgreSQL host ${replacement_postgresql_host} was not added the PE configuration")
  # }
}
