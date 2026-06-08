# Assert that the replica's pe-puppetdb database and service survive a PE upgrade.
#
# PE-44247 / PE-44245: PuppetDB does not use pglogical for HA sync, so the
# pe-puppetdb database is not covered by the pglogical-based DB-sync checks. During
# a major PostgreSQL upgrade of an HA cluster (e.g. PG14 -> PG17 driven by
# puppet_enterprise::postgres_version_override) the replica's pe-puppetdb database
# was dropped and never recreated, leaving the pe-puppetdb service stuck in
# 'activating'. The routing fix landed in puppet-enterprise-modules; this plan is
# the peadm::upgrade-path regression guard for it.
#
# It is the peadm analogue of pe_acceptance_tests'
# acceptance/high_availability/tests/provision_replica/040_provision_replica_verify_puppetdb_database.rb
# (which guards the legacy `puppet infrastructure upgrade replica` path). The
# assertions hold for any healthy HA replica -- they pass without a PG-major
# upgrade and fail on the PE-44245 regression when one occurs.
plan peadm_spec::verify_replica_pe_puppetdb() {
  $t = get_targets('*')
  wait_until_available($t)

  $replica_host = $t.filter |$n| { $n.vars['role'] == 'replica' }

  if $replica_host == [] {
    fail_plan('"replica" role missing from inventory, cannot verify pe-puppetdb on the replica')
  }

  # /opt/puppetlabs/server/bin/psql is the version-agnostic wrapper, so this still
  # targets the *active* PostgreSQL major version's catalog after a PG-major
  # upgrade. `psql -l` avoids embedding a quoted SQL literal in the `su -c`
  # command. A missing pe-puppetdb database is the PE-44245 regression, so fail
  # fast rather than retry it away.
  out::message('PE-44247: verifying the pe-puppetdb database exists on the replica')
  run_command(
    "su -s /bin/bash pe-postgres -c \"/opt/puppetlabs/server/bin/psql -lqt | cut -d'|' -f1 | grep -qw pe-puppetdb\"",
    $replica_host,
    'pe-puppetdb database is missing on the replica (PE-44245 regression)',
  )

  # With the database missing, the service hangs in 'activating' indefinitely, so
  # assert it actually reaches 'active'. Retry to let services settle after the
  # upgrade rather than asserting on a single sample.
  out::message('PE-44247: verifying the pe-puppetdb service is active on the replica')
  $tries = 30
  $interval = 10
  $active = range(1, $tries).reduce(false) |$found, $_attempt| {
    if $found {
      true
    } else {
      $status = run_command('systemctl is-active pe-puppetdb', $replica_host, '_catch_errors' => true).first['stdout'].strip
      if $status == 'active' {
        true
      } else {
        ctrl::sleep($interval)
        false
      }
    }
  }

  unless $active {
    fail_plan("pe-puppetdb service on the replica did not reach 'active' within ${tries * $interval}s (PE-44245 regression)")
  }

  out::message('PE-44247: replica pe-puppetdb database present and service active')
}
