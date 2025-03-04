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
  # pre-migration checks
  peadm::assert_supported_bolt_version()
  peadm::assert_supported_pe_version($pe_version, $permit_unsafe_versions)

  $all_hosts = peadm::flatten_compact([
      $old_primary_host,
      $new_primary_host,
  ])
  run_command('hostname', $all_hosts)  # verify can connect to targets

  # verify the cluster we are migrating from is operational and is a supported architecture
  $cluster = run_task('peadm::get_peadm_config', $targets).first.value
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

  $backup_file = run_plan('peadm::backup', $old_primary_host, {
      backup_type => 'migration',
  })

  download_file($backup_file['path'], 'backup', $old_primary_host)

  $backup_filename = basename($backup_file['path'])
  $remote_backup_path = "/tmp/${backup_filename}"
  $current_dir = system::env('PWD')

  upload_file("${current_dir}/downloads/backup/${old_primary_host}/${backup_filename}", $remote_backup_path, $new_primary_host)

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
