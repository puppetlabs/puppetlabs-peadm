plan peadm_spec::verify_replica() {
  $t = get_targets('*')
  wait_until_available($t)

  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }

  if $primary_host == [] {
    fail_plan('"primary" role missing from inventory, cannot continue')
  }

  $result = run_task('peadm::get_peadm_config', $primary_host, '_catch_errors' => true).first.to_data()

  $replica_host = $result['value']['params']['replica_host']

  if $replica_host == undef or $replica_host == null {
    fail_plan("No replica was found in the PE configuration")
  } else {
    out::message("Replica added successfully: ${replica_host}")
  }

  # PE-44999: extra-large-with-dr gives the replica a dedicated PostgreSQL host, so
  # replica_postgresql_host has to be confirmed as well. Gated on the inventory role
  # only: extra-large-and-spare-replica also has a split-database primary but no
  # replica PostgreSQL host, which is valid.
  $replica_postgresql_inventory = $t.filter |$n| { $n.vars['role'] == 'replica-pdb-postgresql' }

  unless $replica_postgresql_inventory == [] {
    $replica_postgresql_host = $result['value']['params']['replica_postgresql_host']

    unless $replica_postgresql_host =~ String[1] {
      fail_plan('No replica_postgresql_host was found in the PE configuration')
    }

    if $replica_postgresql_host == $result['value']['params']['primary_postgresql_host'] {
      fail_plan("replica_postgresql_host (${replica_postgresql_host}) is the same as primary_postgresql_host")
    }

    out::message("Replica PostgreSQL host configured: ${replica_postgresql_host}")
  }
}
