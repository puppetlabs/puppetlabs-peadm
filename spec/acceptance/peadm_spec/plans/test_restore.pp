plan peadm_spec::test_restore() {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }[0]

  $input_file = run_command('ls /tmp/pe-backup*gz', $primary_host)

  run_plan('peadm::restore', $primary_host, { 'restore_type' => 'recovery', 'input_file' => $input_file })

  # run infra status on the primary
  out::message("Running peadm::status on primary host ${primary_host}")
  $result = run_plan('peadm::status', $primary_host, { 'format' => 'json' })

  out::message($result)

  if empty($result['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }
}
