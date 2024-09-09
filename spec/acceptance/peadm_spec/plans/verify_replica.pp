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
}