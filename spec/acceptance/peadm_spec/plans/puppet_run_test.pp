plan peadm_spec::puppet_run_test() {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $cert = $target.set_var('certname', $fqdn.first['stdout'].chomp)

    out::message("Running puppet on host ${cert}.")

    $status = run_task('peadm::puppet_runonce', $target).first.status

    # Checking for success based on the exit code
    if $status == 'success' {
      out::message("Puppet run succeeded on ${cert}.")
    } else {
      fail_plan("Puppet run failed on ${cert}.")
    }
  }
}
