plan peadm_spec::puppet_run_test() {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  # run puppet on the primary
  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }[0]
  out::message("Running puppet on primary host ${primary_host}")

  $status = run_task('peadm::puppet_runonce', $primary_host).first.status

  # Checking for success based on the exit code
  if $status == 'success' {
    out::message('Puppet run succeeded on the primary host.')
  } else {
    fail_plan('Puppet run failed on the primary host.')
  }
}
