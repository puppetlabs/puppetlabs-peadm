plan peadm_spec::test_replace_failed_postgres(
  Peadm::SingleTargetSpec   $primary_host,
  Peadm::SingleTargetSpec   $replica_host,
  Peadm::SingleTargetSpec   $working_postgresql_host,
  Peadm::SingleTargetSpec   $failed_postgresql_host,
  Peadm::SingleTargetSpec   $replacement_postgresql_host,
) {
  # run infra status on the primary
  out::message("Running peadm::status on primary host ${primary_host}")
  $primary_status = run_plan('peadm::status', $primary_host, { 'format' => 'json' })
  out::message($primary_status)

  if empty($primary_status['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }

  run_plan('peadm::replace_failed_postgresql',
    primary_host => $primary_host,
    replica_host => $replica_host,
    working_postgresql_host => $working_postgresql_host,
    failed_postgresql_host => $failed_postgresql_host,
    replacement_postgresql_host => $replacement_postgresql_host,
  )

  # get the config from primary_host and verify failed_postgresql_host is removed and replacement was added
  $result = run_task('peadm::get_peadm_config', $primary_host, '_catch_errors' => true).first.to_data()
  out::message("PE configuration: ${result}")
  $primary_postgres_host = $result['value']['params']['primary_postgresql_host']
  $replica_postgres_host = $result['value']['params']['replica_postgresql_host']

  out::message("Primary PostgreSQL host: ${primary_postgres_host}")
  out::message("Replica PostgreSQL host: ${replica_postgres_host}")
  out::message("working_postgresql_host: ${working_postgresql_host}")
  out::message("failed_postgresql_host: ${failed_postgresql_host}")
  out::message("replacement_postgresql_host: ${replacement_postgresql_host}")
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
