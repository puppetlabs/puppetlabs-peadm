plan peadm_spec::upgrade_test_cluster(
  $version,
  $download_mode
){

  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }
  $replica_host = $t.filter |$n| { $n.vars['role'] == 'replica' }
  $replica_postgresql_host = $t.filter |$n| { $n.vars['role'] == 'replica-pdb-postgresql' }

  if $replica_host == [] {
    fail_plan('"replica" role missing from inventory, cannot continue')
  }

  $params = {
    primary_host            => $primary_host,
    replica_host            => $replica_host,
    replica_postgresql_host => $replica_postgresql_host ? { [] => undef, default => $replica_postgresql_host },
    download_mode           => 'direct',
    version                 => $version,
  }

  # run_plan('peadm::upgrade', $params)
}
