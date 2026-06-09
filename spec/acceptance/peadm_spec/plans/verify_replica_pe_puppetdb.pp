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
# (which guards the legacy `puppet infrastructure upgrade replica` path).
#
# The pe-puppetdb database/service assertions hold for any healthy HA replica --
# they pass without a PG-major upgrade and fail on the PE-44245 regression when one
# occurs. On their own that makes them blind to a silently-skipped upgrade (e.g.
# the override never landing in pe.conf), which would leave the replica on its
# original PG major with the database intact and this test green having tested
# nothing. The optional $expected_psql_version anchors that: run the plan
# pre-upgrade asserting the UPGRADE_FROM major (PG14) and post-upgrade asserting the
# forced major (PG17) to prove the boundary was actually crossed.
plan peadm_spec::verify_replica_pe_puppetdb(
  # PE-44247: when set, assert the replica's active PostgreSQL major version equals
  # this value before running the pe-puppetdb checks. Leave unset to skip the
  # version assertion.
  Optional[String[1]] $expected_psql_version = undef,
) {
  $t = get_targets('*')
  wait_until_available($t)

  $replica_host = $t.filter |$n| { $n.vars['role'] == 'replica' }

  if $replica_host == [] {
    fail_plan('"replica" role missing from inventory, cannot verify pe-puppetdb on the replica')
  }

  # PE-44247: anchor the upgrade by asserting the replica's active PG major. In
  # standard-with-dr PostgreSQL is colocated on the replica, so peadm::get_psql_version
  # (PEPostgresqlInfo#installed_server_version) run there reports the active major.
  # A mismatch means the PG-major upgrade did not take effect on the replica -- the
  # exact silent failure the pe-puppetdb checks below cannot detect on their own.
  if $expected_psql_version =~ NotUndef {
    out::message("PE-44247: verifying the replica is on PostgreSQL ${expected_psql_version}")
    $actual_psql_version = String(run_task('peadm::get_psql_version', $replica_host).first.value['version'])
    unless $actual_psql_version == $expected_psql_version {
      fail_plan("replica PostgreSQL major version is ${actual_psql_version}, expected ${expected_psql_version} (PG-major upgrade did not take effect on the replica)") # lint:ignore:140chars
    }
    out::message("PE-44247: replica is on PostgreSQL ${actual_psql_version}")
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
