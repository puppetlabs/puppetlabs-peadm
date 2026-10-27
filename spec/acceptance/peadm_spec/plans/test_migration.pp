plan peadm_spec::test_migration(
  String $primary_host,
  String $new_primary_host,
  Optional[String] $new_replica_host = undef,
  Optional[String] $new_primary_postgresql_host = undef,
  Optional[String] $new_replica_postgresql_host = undef,
  Optional[String] $upgrade_version = undef,
  # Fail, rather than warn, when the CA has no pe-ca database to check the primary's serial in. The
  # default is warn-only because PE lines without a database-backed CA have no pe-ca; the CI
  # workflow does not set it, so set it for runs that must prove the registration check ran.
  Boolean $require_ca_database = false,
) {
  # Convert String values to targets if they are not blank
  $primary_target = $primary_host ? { '' => undef, default => peadm::get_targets($primary_host, 1) }
  $new_primary_target = $new_primary_host ? { '' => undef, default => peadm::get_targets($new_primary_host, 1) }
  $new_replica_target = $new_replica_host ? { '' => undef, default => peadm::get_targets($new_replica_host, 1) }
  $new_primary_postgresql_target = $new_primary_postgresql_host ? { '' => undef, default => peadm::get_targets($new_primary_postgresql_host, 1) }
  $new_replica_postgresql_target = $new_replica_postgresql_host ? { '' => undef, default => peadm::get_targets($new_replica_postgresql_host, 1) }

  # run infra status on the primary
  out::message("Running peadm::status on primary host ${primary_target}")
  $primary_status = run_plan('peadm::status', $primary_target, { 'format' => 'json' })
  out::message($primary_status)

  if empty($primary_status['failed']) {
    out::message('Cluster is healthy, continuing')
  } else {
    fail_plan('Cluster is not healthy, aborting')
  }

  # perform the migration
  run_plan('peadm::migrate',
    old_primary_host => $primary_target,
    new_primary_host => $new_primary_target,
    upgrade_version => $upgrade_version,
    replica_host => $new_replica_target,
    primary_postgresql_host => $new_primary_postgresql_target,
    replica_postgresql_host => $new_replica_postgresql_target,
  )

  # run infra status on the new primary
  peadm::wait_until_service_ready('all', $new_primary_target)
  out::message("Running peadm::status on new primary host ${new_primary_target}")
  $new_primary_status = run_plan('peadm::status', $new_primary_target, { 'format' => 'json' })
  if empty($new_primary_status['failed']) {
    out::message('Migrated cluster is healthy, continuing')
  } else {
    out::message('Migrated cluster is not healthy, verify status of services')
  }

  # PE-47864: the new primary's own certificate must not be revoked, and when the CA keeps a
  # pe-ca database its serial must be registered there exactly once with no serial issued twice.
  # A certificate numbered from a stale filesystem serial counter (PE-47863) carries a serial the
  # database never recorded or already gave to another certificate, so revoking that other holder
  # revokes the primary. This runs after peadm::migrate, so it checks the end state, not that the
  # certificate was regenerated.
  $new_primary_certname = $new_primary_target.peadm::certname()
  $cert_status = run_task('peadm_spec::primary_cert_status', $new_primary_target,
    'certname' => $new_primary_certname,
  ).first.value
  $primary_serial = $cert_status['serial']
  out::message("New primary ${new_primary_certname} certificate serial: ${primary_serial}")

  # Anything but an explicit false fails, so a task result missing the key cannot pass.
  if $cert_status['in_crl'] != false {
    fail_plan("New primary serial ${primary_serial} is not confirmed out of the CRL (in_crl=${cert_status['in_crl']}): primary revoked")
  }

  # pe-ca may live on a dedicated PostgreSQL host (install.pp only moves PuppetDB's database there,
  # but the comment citing PE-45431 in install.pp implies pe-ca is created on the database targets),
  # so look on that host first and fall back to the primary. The fallback covers only "no pe-ca
  # table"; a host that cannot be queried at all fails the task. $new_primary_postgresql_target is
  # undef for '' and [] for an omitted parameter (peadm::get_targets(undef)), so match on the type
  # rather than on undef.
  if $new_primary_postgresql_target =~ Array[Target, 1, 1] {
    $ca_database_target = $new_primary_postgresql_target
  } else {
    $ca_database_target = $new_primary_target
  }
  $first_registration = run_task('peadm_spec::ca_serial_registered', $ca_database_target,
    'certname' => $new_primary_certname,
    'serial'   => $primary_serial,
  ).first.value
  # Like in_crl above, a result without a Boolean table_present must not pass quietly.
  if $first_registration['table_present'] !~ Boolean {
    fail_plan("peadm_spec::ca_serial_registered returned no table_present flag: ${first_registration}")
  }
  $ca_database_certname = $ca_database_target.peadm::certname()
  $ca_hosts_looked_on = [$ca_database_certname, $new_primary_certname].unique.join(', ')
  if !$first_registration['table_present'] and $ca_database_certname != $new_primary_certname {
    $registration = run_task('peadm_spec::ca_serial_registered', $new_primary_target,
      'certname' => $new_primary_certname,
      'serial'   => $primary_serial,
    ).first.value
    if $registration['table_present'] !~ Boolean {
      fail_plan("peadm_spec::ca_serial_registered returned no table_present flag: ${registration}")
    }
  } else {
    $registration = $first_registration
  }

  if $registration['table_present'] {
    if $registration['count'] != 1 {
      fail_plan("Expected 1 pe-ca row for ${new_primary_certname} serial ${primary_serial}, found ${registration['count']}")
    }
    if $registration['duplicates'] != 0 {
      fail_plan("${registration['duplicates']} serial(s) appear on more than one ca_signed_certificates row")
    }
    out::message("The new primary's serial ${primary_serial} is registered once in the CA database")
  } else {
    # Only reached when the query ran and found no pe-ca database or no ca_signed_certificates
    # table on any host it looked on (${ca_database_certname}, then the primary when they differ); a
    # failing query aborts the task. Say so loudly: this check did not run.
    if $require_ca_database {
      fail_plan("No pe-ca table on ${ca_hosts_looked_on}, and require_ca_database is set")
    }
    out::message("WARNING: no pe-ca table on ${ca_hosts_looked_on}, registration check skipped")
  }

  # get the config from new_primary_target and verify config looks as expected
  $peadm_config = run_task('peadm::get_peadm_config', $new_primary_target).first.value
  out::message("peadm_config:${peadm_config}.")
  # if new_replica_target is supplied then check that is in the expected place in the config
  if $new_replica_target {
    if $peadm_config['params']['replica_host'] == $new_replica_target.peadm::certname() {
      out::message("New replica host ${new_replica_target.peadm::certname()} set up correctly")
    } else {
      fail_plan("New replica host ${new_replica_target.peadm::certname()} was not set up correctly")
    }
  }

  # if new_primary_postgresql_target is supplied then check that is in the expected place in the config
  if $new_primary_postgresql_target {
    if $peadm_config['params']['primary_postgresql_host'] == $new_primary_postgresql_target.peadm::certname() {
      out::message("New primary postgres host ${new_primary_postgresql_target.peadm::certname()} set up correctly")
    } else {
      fail_plan("New primary postgres host ${new_primary_postgresql_target.peadm::certname()} was not set up correctly")
    }
  }

  # if new_replica_postgresql_target is supplied then check that is in the expected place in the config
  if $new_replica_postgresql_target {
    if $peadm_config['params']['replica_postgresql_host'] == $new_replica_postgresql_target.peadm::certname() {
      out::message("New replica postgres host ${new_replica_postgresql_target.peadm::certname()} set up correctly")
    } else {
      fail_plan("New replica postgres host ${new_replica_postgresql_target.peadm::certname()} was not set up correctly")
    }
  }

  # if a new PE version was specified then check it has been upgraded
  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    if $peadm_config['pe_version'] == $upgrade_version {
      out::message("Upgraded to new PE version ${upgrade_version} correctly")
    } else {
      fail_plan("Failed to upgrade to new PE version ${upgrade_version} correctly")
    }
  }
}
