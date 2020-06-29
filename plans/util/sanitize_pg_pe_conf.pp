plan peadm::util::sanitize_pg_pe_conf (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $master_host,
) {
  $master_target = get_target($master_host)

  # Ensure the pe.conf file on PostgreSQL nodes has the needed values for
  # puppet_master_host and database_host
  run_task('peadm::read_file', $targets,
    path => '/etc/puppetlabs/enterprise/conf.d/pe.conf',
  ).map |$result| {
    $sanitized = $result['content'].loadjson() + {
      'puppet_enterprise::puppet_master_host' => $master_target.peadm::target_name(),
      'puppet_enterprise::database_host'      => $result.target.peadm::target_name(),
    }
    # Return the result of file_content_upload. There is only one target
    peadm::file_content_upload($sanitized, $result.target)[0]
  }
}
