# @summary Replaces a failed PostgreSQL host
# @param primary_host - The hostname and certname of the primary Puppet server
# @param replica_host - The hostname and certname of the replica VM
# @param working_postgresql_host - The hostname and certname of the still-working PE-PostgreSQL server
# @param failed_postgresql_host - The hostname and certname of the failed PE-PostgreSQL server
# @param replacement_postgresql_host - The hostname and certname of the server being brought in to replace the failed PE-PostgreSQL server
#
plan peadm::replace_failed_postgresql(
  Peadm::SingleTargetSpec   $primary_host,
  Peadm::SingleTargetSpec   $replica_host,
  Peadm::SingleTargetSpec   $working_postgresql_host,
  Peadm::SingleTargetSpec   $failed_postgresql_host,
  Peadm::SingleTargetSpec   $replacement_postgresql_host,
) {
  $all_hosts = peadm::flatten_compact([
      $primary_host,
      $replica_host,
      $working_postgresql_host,
      $failed_postgresql_host,
      $replacement_postgresql_host,
  ])

  # verify we can connect to targets proded before proceeding
  run_command('hostname', $all_hosts)

  # Get current peadm config before making modifications
  $peadm_config = run_task('peadm::get_peadm_config', $primary_host).first.value
  $compilers = $peadm_config['params']['compilers']

  # Bail if we are not running this against an XL deployment with DR enabled - the parameters also enforce this to some extent
  if $compilers.empty {
    fail_plan('Plan peadm::replace_failed_postgresql is only applicable for XL deployments with DR enabled')
  }

  $pe_hosts = peadm::flatten_compact([
      $primary_host,
      $replica_host,
  ])

  # Stop puppet.service on Puppet server primary and replica
  run_task('service', $pe_hosts, 'action' => 'stop', 'name' => 'puppet.service')

  # Temporarily set both primary and replica server nodes so that they use the remaining healthy PE-PostgreSQL server
  run_plan('peadm::util::update_db_setting', $pe_hosts,
    postgresql_host => $working_postgresql_host,
    override => true,
  )

  # Restart pe-puppetdb.service on Puppet server primary and replica
  run_task('service', $pe_hosts, { action => 'restart', name => 'pe-puppetdb.service' })

  # Purge failed PE-PostgreSQL node from PuppetDB
  run_command("/opt/puppetlabs/bin/puppet node purge ${$failed_postgresql_host}", $primary_host)

  # Run peadm::add_database plan to deploy replacement PE-PostgreSQL server
  run_plan('peadm::add_database', targets => $replacement_postgresql_host,
    primary_host => $primary_host,
  )
}
