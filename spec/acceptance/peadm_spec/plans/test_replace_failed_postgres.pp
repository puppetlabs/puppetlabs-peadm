plan peadm_spec::test_replace_failed_postgres(
  Peadm::SingleTargetSpec   $primary_host,
  Peadm::SingleTargetSpec   $replica_host,
  Peadm::SingleTargetSpec   $working_postgresql_host,
  Peadm::SingleTargetSpec   $failed_postgresql_host,
  Peadm::SingleTargetSpec   $replacement_postgresql_host,
) {
  # run puppet once on working_postgresql_host - gives some time in CI
  run_task('peadm::puppet_runonce', $working_postgresql_host)

  # replace the failed postgres server
  run_plan('peadm::replace_failed_postgresql',
    primary_host => $primary_host,
    replica_host => $replica_host,
    working_postgresql_host => $working_postgresql_host,
    failed_postgresql_host => $failed_postgresql_host,
    replacement_postgresql_host => $replacement_postgresql_host,
  )

  # get the config from primary_host and verify failed_postgresql_host is removed and replacement was added
  $result = run_task('peadm::get_peadm_config', $primary_host, '_catch_errors' => true).first.to_data()
  $primary_postgres_host = $result['value']['params']['primary_postgresql_host']
  $replica_postgres_host = $result['value']['params']['replica_postgresql_host']

  if $primary_postgres_host == $failed_postgresql_host or $replica_postgres_host == $failed_postgresql_host {
    fail_plan("Failed PostgreSQL host ${failed_postgresql_host} was not removed from the PE configuration")
  } else {
    out::message("Failed PostgreSQL host ${failed_postgresql_host} was removed from the PE configuration")
  }
  if $primary_postgres_host == $replacement_postgresql_host or $replica_postgres_host == $replacement_postgresql_host {
    out::message("Replacement PostgreSQL host ${replacement_postgresql_host} was added to the PE configuration")
  } else {
    fail_plan("Replacement PostgreSQL host ${replacement_postgresql_host} was not added the PE configuration")
  }
}
