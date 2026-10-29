# PE-47523: install uploads a bootstrap /tmp/pe.conf to the primary and the
# PostgreSQL nodes and must remove it once the installer has run; the
# primary's copy holds the console password. Fails for any node where the
# check doesn't pass, including one where it couldn't run.
plan peadm_spec::verify_no_bootstrap_pe_conf() {
  $t = get_targets('*')
  wait_until_available($t)

  $results = run_command('test ! -e /tmp/pe.conf', $t, '_catch_errors' => true)

  unless $results.ok {
    fail_plan("/tmp/pe.conf is still present, or could not be checked, on ${results.error_set.names.join(', ')}")
  }

  out::message('No node has /tmp/pe.conf')
}
