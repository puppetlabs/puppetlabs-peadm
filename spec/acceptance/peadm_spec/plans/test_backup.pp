plan peadm_spec::test_backup() {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

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
  run_plan('peadm::backup', $primary_host, { 'output_directory' => '/tmp', 'backup_type' => 'recovery' })
}
