plan peadm_spec::verify_config(
  Peadm::SingleTargetSpec           $primary_host,
) {
  $primary_target = peadm::get_targets($primary_host, 1)

  out::message("Running peadm::status on primary host ${primary_host}")
  $result = run_plan('peadm::status', $primary_host, { 'format' => 'json' })

  out::message($result)

  if empty($result['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }

  $result = run_task('peadm::get_peadm_config', $primary_host, '_catch_errors' => true).first.to_data()
  out::message("PE configuration: ${result}")
  $replica_host = $result['value']['params']['replica_host']
  out::message("Replica host: ${replica_host}")
  if $replica_host == undef or $replica_host == null {
    out::message('No replica was found in the PE configuration')
  } else {
    out::message("Replica added successfully: ${replica_host}")
  }
}
