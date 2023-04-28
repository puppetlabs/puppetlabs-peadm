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
  run_plan('peadm::status', $primary_host)

  $backup_options = {
    'orchestrator' => true,
    'puppetdb' => true,
    'rbac' => true,
    'activity' => true,
    'ca' => true,
    'classifier' => true,
  }
  run_plan('peadm::backup', $primary_host, { 'output_directory' => '/tmp', 'backup' => $backup_options })
}
