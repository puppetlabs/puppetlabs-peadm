plan peadm_spec::test_replace_failed_postgres(
  Peadm::SingleTargetSpec   $primary_host,
  Peadm::SingleTargetSpec   $replica_host,
  Peadm::SingleTargetSpec   $working_postgresql_host,
  Peadm::SingleTargetSpec   $failed_postgresql_host,
  Peadm::SingleTargetSpec   $replacement_postgresql_host,
) {
  $primary_fqdn = run_command('hostname -f', $primary_host).first['stdout'].chomp
  $replica_fqdn = run_command('hostname -f', $replica_host).first['stdout'].chomp
  $working_postgres_fqdn = run_command('hostname -f', $working_postgresql_host).first['stdout'].chomp
  $failed_postgres_fqdn = run_command('hostname -f', $failed_postgresql_host).first['stdout'].chomp
  $replacement_postgres_fqdn = run_command('hostname -f', $replacement_postgresql_host).first['stdout'].chomp

  # run infra status on the primary
  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }[0]
  out::message("Running peadm::status on primary host ${primary_host}")
  $result = run_plan('peadm::status', $primary_host, { 'format' => 'json' })

  out::message($result)

  if empty($result['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }
  run_plan('peadm::replace_failed_postgresql',
    primary_host => $primary_fqdn,
    replica_host => $replica_fqdn,
    working_postgresql_host => $working_postgresql_fqdn,
    failed_postgresql_host => $failed_postgresql_fqdn,
    replacement_postgresql_host => $replacement_postgresql_fqdn,
  )
}
