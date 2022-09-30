plan peadm_spec::perform_failover(
  String[1] $console_password
) {
  # get node certnames
  $t = get_targets('*')
  # wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  # run infra status on the primary
  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }
  # out::verbose("Running peadm::status on new primary host ${primary_host}")
  # run_plan('peadm::status', $primary_host)

  # # bring down the current primary
  # out::verbose("Bringing down primary host ${primary_host}")
  # run_task('reboot', $primary_host, shutdown_only => true)

  # promote the replica to new primary
  $replica_host = $t.filter |$n| { $n.vars['role'] == 'replica' }
  # out::verbose("Promoting replica host ${replica_host} to primary")
  # run_command(@("HEREDOC"/L), $replica_host)
  #   /opt/puppetlabs/bin/puppet infra promote replica --topology mono-with-compile --yes
  # |-HEREDOC

  # generate access token
  out::verbose("Generating access token on replica host ${replica_host}")
  run_task('peadm::rbac_token', $replica_host,
    password       => $console_password,
    token_lifetime => '1y',
  )

  # $primary_certname = $primary_host.peadm::certname()
  # purge the "failed" primary node
  run_command(@("HEREDOC"/L), $replica_host)
    # /opt/puppetlabs/bin/puppet node purge ${peadm::certname($primary_host)}
    /opt/puppetlabs/bin/puppet node purge ip-10-138-1-143.eu-central-1.compute.internal
  |-HEREDOC

  # add new replica
  $replica_postgresql_host = $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' }
  $new_replica_host = $t.filter |$n| { $n.vars['role'] == 'spare-replica' }

  if $new_replica_host == [] {
    fail_plan('"spare-replica" role missing from inventory, cannot continue')
  }

  out::verbose("Adding new replica host ${new_replica_host} to primary")
  run_plan('peadm::add_replica',
    primary_host            => $replica_host.first(),
    replica_host            => $new_replica_host.first(),
    replica_postgresql_host => $replica_postgresql_host ? { [] => undef, default => $replica_postgresql_host.first() },
  )

  # run infra status on the new primary
  out::verbose("Running peadm::status on new primary host ${replica_host}")
  run_plan('peadm::status', $replica_host)

  out::message('Failover process complete. New configuration:')
  run_task('peadm::get_peadm_config', $replica_host)
}
