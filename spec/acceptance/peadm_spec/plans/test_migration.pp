plan peadm_spec::test_migration(
  String $primary_host,
  String $new_primary_host,
  Optional[String] $new_replica_host = undef,
  Optional[String] $new_primary_postgresql_host = undef,
  Optional[String] $new_replica_postgresql_host = undef,
  Optional[String] $upgrade_version = undef,
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
  #
  # CI WORKAROUND (Bucket B disk exhaustion): when an upgrade is requested we run
  # the migration and the upgrade as two separate steps so that disk can be
  # reclaimed on the new primary in between. The PE major-version upgrade's
  # PostgreSQL migration pre-flight requires free space >= the current DB size on
  # the PG data filesystem, and the CI VM's / is too small while the stale old
  # installer media (left extracted under /tmp by pe_install.sh) is still present.
  # Removing it clears the margin. This is a test-harness-only change; the real
  # fix is sizing up the CI VM disk in the provision service.
  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    run_plan('peadm::migrate',
      old_primary_host => $primary_target,
      new_primary_host => $new_primary_target,
      replica_host => $new_replica_target,
      primary_postgresql_host => $new_primary_postgresql_target,
      replica_postgresql_host => $new_replica_postgresql_target,
    )

    # Reclaim disk on the new primary before the major-version upgrade runs.
    run_command('rm -rf /tmp/puppet-enterprise-*/ /tmp/puppet-enterprise-*.tar.gz 2>/dev/null || true; (dnf clean all || yum clean all) 2>/dev/null || true; rm -rf /var/cache/dnf/* /var/cache/yum/* 2>/dev/null || true; journalctl --vacuum-size=20M 2>/dev/null || true', $new_primary_target)

    run_plan('peadm::upgrade',
      primary_host => $new_primary_target,
      version => $upgrade_version,
      replica_host => $new_replica_target,
      primary_postgresql_host => $new_primary_postgresql_target,
      replica_postgresql_host => $new_replica_postgresql_target,
      download_mode => 'direct',
    )
  } else {
    run_plan('peadm::migrate',
      old_primary_host => $primary_target,
      new_primary_host => $new_primary_target,
      replica_host => $new_replica_target,
      primary_postgresql_host => $new_primary_postgresql_target,
      replica_postgresql_host => $new_replica_postgresql_target,
    )
  }

  # run infra status on the new primary
  peadm::wait_until_service_ready('all', $new_primary_target)
  out::message("Running peadm::status on new primary host ${new_primary_target}")
  $new_primary_status = run_plan('peadm::status', $new_primary_target, { 'format' => 'json' })
  if empty($new_primary_status['failed']) {
    out::message('Migrated cluster is healthy, continuing')
  } else {
    out::message('Migrated cluster is not healthy, verify status of services')
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
