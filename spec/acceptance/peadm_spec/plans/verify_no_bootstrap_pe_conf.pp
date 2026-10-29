# PE-47523: install uploads a bootstrap /tmp/pe.conf, which holds the console
# password, to the primary and the PostgreSQL nodes, and must remove it once
# the installer has run.
plan peadm_spec::verify_no_bootstrap_pe_conf() {
  $t = get_targets('*')
  wait_until_available($t)

  $results = run_command('if [ -e /tmp/pe.conf ]; then echo present; fi', $t)
  $present = $results.filter |$result| { $result['stdout'].strip == 'present' }.map |$result| { $result.target.name }

  unless $present.empty {
    fail_plan("/tmp/pe.conf is still present on ${present.join(', ')}")
  }

  out::message('No node has /tmp/pe.conf')
}
