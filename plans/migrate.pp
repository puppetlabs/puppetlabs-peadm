# @summary Migrate a PE primary server to a new host
#
# @param old_primary_host
#   The existing PE primary server that will be migrated from
# @param new_primary_host
#   The new server that will become the PE primary server
# @param upgrade_version
#   Optional version to upgrade to after migration is complete
#
plan peadm::migrate (
  Peadm::SingleTargetSpec $old_primary_host,
  Peadm::SingleTargetSpec $new_primary_host,
  Optional[String] $upgrade_version = undef,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,
) {
  peadm::assert_supported_bolt_version()

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

  out::message("old_pe_conf:${old_pe_conf}.")

  run_plan('peadm::install', {
      primary_host                => $new_primary_host,
      console_password            => $old_primary_password,
      code_manager_auto_configure => true,
      download_mode               => 'direct',
      version                     => $old_pe_conf['pe_version'],
  })

  run_plan('peadm::restore', {
      targets => $new_primary_host,
      restore_type => 'migration',
      input_file => $remote_backup_path,
  })

  # Get the new PE configuration
  $new_primary_target = get_targets($new_primary_host)[0]
  $new_pe_conf = run_task('peadm::get_peadm_config', $new_primary_target).first.value
  out::message("new_pe_conf before purging: ${new_pe_conf}")

  # Use the old PE configuration to determine which nodes to purge
  # Create separate variables for each component to purge
  $old_primary_host_value = $old_pe_conf['params']['primary_host']
  $replica_host_value = $old_pe_conf['params']['replica_host']
  $primary_postgresql_host_value = $old_pe_conf['params']['primary_postgresql_host']
  $replica_postgresql_host_value = $old_pe_conf['params']['replica_postgresql_host']
  $compilers_value = $old_pe_conf['params']['compilers']
  $legacy_compilers_value = $old_pe_conf['params']['legacy_compilers']

  # Build the purge string components
  $old_primary_host_string = !empty($old_primary_host_value) ? {
    true    => $old_primary_host_value,
    default => ''
  }

  $replica_host_string = !empty($replica_host_value) ? {
    true    => $replica_host_value,
    default => ''
  }

  $primary_postgresql_host_string = !empty($primary_postgresql_host_value) ? {
    true    => $primary_postgresql_host_value,
    default => ''
  }

  $replica_postgresql_host_string = !empty($replica_postgresql_host_value) ? {
    true    => $replica_postgresql_host_value,
    default => ''
  }

  $compilers_string = !empty($compilers_value) ? {
    true    => $compilers_value.filter |$node| { !empty($node) }.join(','),
    default => ''
  }

  $legacy_compilers_string = !empty($legacy_compilers_value) ? {
    true    => $legacy_compilers_value.filter |$node| { !empty($node) }.join(','),
    default => ''
  }

  # Combine all non-empty strings with commas
  $purge_components = [
    $replica_host_string,
    $primary_postgresql_host_string,
    $replica_postgresql_host_string,
    $compilers_string,
    $legacy_compilers_string,
    $old_primary_host_string,
  ].filter |$component| { !empty($component) }

  $purge_string = $purge_components.join(',')

  # Purge the nodes if we have any
  if !empty($purge_string) {
    out::message("Purging nodes from old configuration: ${purge_string}")
    run_command("/opt/puppetlabs/bin/puppet node purge ${purge_string}", $new_primary_host)
  } else {
    out::message("No nodes to purge from old configuration")
  }

  # Get updated PE configuration after purging
  $updated_pe_conf = run_task('peadm::get_peadm_config', $new_primary_target).first.value
  out::message("new_pe_conf after purging: ${updated_pe_conf}")

  if $replica_host {
    run_plan('peadm::add_replica', {
        primary_host => $new_primary_host,
        replica_host => $replica_host,
    })
  }

  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    run_plan('peadm::upgrade', {
        primary_host                => $new_primary_host,
        version                     => $upgrade_version,
        download_mode               => 'direct',
        replica_host                => $replica_host,
    })
  }
}
