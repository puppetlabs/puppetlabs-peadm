# @summary Migrate a PE installation to new host(s)
#
# @param old_primary_host
#   The existing PE primary server that will be migrated from
# @param new_primary_host
#   The new server that will become the PE primary server
# @param upgrade_version
#   Optional version to upgrade to after migration is complete
# @param replica_host
#   Optional new replica server to be added to the cluster
# @param primary_postgresql_host
#   Optional new primary PostgreSQL server to be added to the cluster
# @param replica_postgresql_host
#   Optional new replica PostgreSQL server to be added to the cluster
plan peadm::migrate (
  Peadm::SingleTargetSpec $old_primary_host,
  Peadm::SingleTargetSpec $new_primary_host,
  Optional[String] $upgrade_version = undef,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,
) {
  # Log parameters for debugging 
  peadm::log_plan_parameters({
    'old_primary_host' => $old_primary_host,
    'new_primary_host' => $new_primary_host,
    'replica_host' => $replica_host,
    'primary_postgresql_host' => $primary_postgresql_host,
    'replica_postgresql_host' => $replica_postgresql_host,
    'upgrade_version' => $upgrade_version,
  })

  # pre-migration checks
  peadm::assert_supported_bolt_version()
  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    $permit_unsafe_versions = false
    peadm::assert_supported_pe_version($upgrade_version, $permit_unsafe_versions)
  }

  $new_hosts = peadm::flatten_compact([
      $new_primary_host,
      $replica_host ? { undef => [], default => [$replica_host] },
      $primary_postgresql_host ? { undef => [], default => [$primary_postgresql_host] },
      $replica_postgresql_host ? { undef => [], default => [$replica_postgresql_host] },
  ].flatten)
  $all_hosts = peadm::flatten_compact([
      $old_primary_host,
      $new_hosts,
  ].flatten)
  run_command('hostname', $all_hosts)  # verify can connect to targets

  # verify the cluster we are migrating from is operational and is a supported architecture
  $cluster = run_task('peadm::get_peadm_config', $old_primary_host).first.value
  $error = getvar('cluster.error')
  if $error {
    fail_plan($error)
  }
  $arch = peadm::assert_supported_architecture(
    getvar('cluster.params.primary_host'),
    getvar('cluster.params.replica_host'),
    getvar('cluster.params.primary_postgresql_host'),
    getvar('cluster.params.replica_postgresql_host'),
    getvar('cluster.params.compiler_hosts'),
  )

  $old_primary_platform = run_task('peadm::precheck', $old_primary_host).first['platform']
  $new_primary_platform = run_task('peadm::precheck', $new_primary_host).first['platform']
  out::message("Old primary platform: ${old_primary_platform}")
  out::message("New primary platform: ${new_primary_platform}")

  $backup_file = run_plan('peadm::backup', $old_primary_host, {
      backup_type => 'migration',
  })

  $download_results = download_file($backup_file['path'], 'backup', $old_primary_host)
  $download_path = $download_results[0]['path']

  $backup_filename = basename($backup_file['path'])
  $remote_backup_path = "/tmp/${backup_filename}"

  upload_file($download_path, $remote_backup_path, $new_primary_host)

  $old_primary_target = get_targets($old_primary_host)[0]
  $old_primary_password = peadm::get_pe_conf($old_primary_target)['console_admin_password']
  $old_pe_conf = run_task('peadm::get_peadm_config', $old_primary_target).first.value

  run_plan('peadm::install', {
      primary_host                => $new_primary_host,
      console_password            => $old_primary_password,
      code_manager_auto_configure => true,
      download_mode               => 'direct',
      version                     => $old_pe_conf['pe_version'],
  })

  run_plan('peadm::restore', {
      targets          => $new_primary_host,
      restore_type     => 'migration',
      input_file       => $remote_backup_path,
      console_password => $old_primary_password,
  })

  $node_types = {
    'primary_host'             => $old_pe_conf['params']['primary_host'],
    'replica_host'             => $old_pe_conf['params']['replica_host'],
    'primary_postgresql_host'  => $old_pe_conf['params']['primary_postgresql_host'],
    'replica_postgresql_host'  => $old_pe_conf['params']['replica_postgresql_host'],
    'compilers'                => $old_pe_conf['params']['compilers'],
    'legacy_compilers'         => $old_pe_conf['params']['legacy_compilers'],
  }

  $nodes_to_purge = $node_types.reduce([]) |$memo, $entry| {
    $value = $entry[1]

    if empty($value) {
      $memo
    }
    elsif $value =~ Array {
      $memo + $value.filter |$node| { !empty($node) }
    }
    else {
      $memo + [$value]
    }
  }

  out::message("Nodes to purge: ${nodes_to_purge}")

  if !empty($nodes_to_purge) {
    out::message('Purging nodes from old configuration individually')
    $nodes_to_purge.each |$node| {
      out::message("Purging node: ${node}")
      run_command("/opt/puppetlabs/bin/puppet node purge ${node}", $new_primary_host)
    }
  } else {
    out::message('No nodes to purge from old configuration')
  }

  # provision a postgresql host if one is provided
  if $primary_postgresql_host {
    run_plan('peadm::add_database', targets => $primary_postgresql_host,
      primary_host => $new_primary_host,
      is_migration => true,
    )
    # provision a replica postgresql host if one is provided
    if $replica_postgresql_host {
      run_plan('peadm::add_database', targets => $replica_postgresql_host,
        primary_host => $new_primary_host,
        is_migration => true,
      )
    }
  }

  # provision a replica if one is provided
  if $replica_host {
    run_plan('peadm::add_replica', {
        primary_host => $new_primary_host,
        replica_host => $replica_host,
        replica_postgresql_host => $replica_postgresql_host,
    })
  }

  # ensure puppet agent enabled on the hosts we migrated to
  run_command('puppet agent --enable', $new_hosts)

  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    run_plan('peadm::upgrade', {
        primary_host                => $new_primary_host,
        version                     => $upgrade_version,
        download_mode               => 'direct',
        replica_host                => $replica_host,
        primary_postgresql_host     => $primary_postgresql_host,
        replica_postgresql_host     => $replica_postgresql_host,
    })
  }
}
