# @summary Migrate a PE primary server to a new host
#
# @param old_primary_host
#   The existing PE primary server that will be migrated from
# @param new_primary_host
#   The new server that will become the PE primary server
#
plan peadm::migrate (
  Peadm::SingleTargetSpec $old_primary_host,
  Peadm::SingleTargetSpec $new_primary_host,
) {
  peadm::assert_supported_bolt_version()

  $backup_file = run_plan('peadm::backup', $old_primary_host, {
      backup_type => 'migration',
  })
  out::message("Backup file: ${backup_file}")
  out::message("Backup file path: ${backup_file['path']}")
  $down_results = download_file($backup_file['path'], 'backup', $old_primary_host)
  out::message("Download results: ${down_results}")
  if $down_results and $down_results[0] and $down_results[0]['value'] and $down_results[0]['value']['path'] {
    out::message("Download results0: ${down_results[0]}")
    if $down_results[0]['value'] {
      out::message("Download results 0 value: ${down_results[0]['value']}")
      if $down_results[0]['value']['path'] {
        out::message("Download results 0 value path: ${down_results[0]['value']['path']}")
        $download_path = $down_results[0]['value']['path']
      } else {
        fail_plan('Failed to download the backup file3. The download results are invalid')
      }
    } else {
      fail_plan('Failed to download the backup file2. The download results are invalid')
    }
    out::message("Download path: ${download_path}")
    out::message("Download path alternate: ${down_results[0]['path']}")
  } else {
    fail_plan('Failed to download the backup file. The download results are invalid.')
  }

  out::message("Download path: ${download_path}")
  $backup_filename = basename($backup_file['path'])
  $remote_backup_path = "/tmp/${backup_filename}"
  $current_dir = system::env('PWD')
  out::message("backup_filename: ${backup_filename}")
  out::message("remote_backup_path: ${remote_backup_path}")
  out::message("current_dir: ${current_dir}")

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
      targets => $new_primary_host,
      restore_type => 'migration',
      input_file => $remote_backup_path,
  })
}
