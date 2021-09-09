# @api private
plan peadm::util::sanitize_pg_pe_conf (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $primary_host,
) {
  $primary_target = get_target($primary_host)

  $path = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
  # Ensure the pe.conf file on PostgreSQL nodes has the needed values for
  # puppet_primary_host and database_host
  run_task('peadm::read_file', $targets,
    path => $path,
  ).map |$result| {
    $sanitized = $result['content'].loadjson() + {
      'puppet_enterprise::puppet_master_host' => $primary_target.peadm::certname(),
      'puppet_enterprise::database_host'      => $result.target.peadm::certname(),
    }
    # Return the result of file_content_upload. There is only one target
    peadm::file_content_upload($sanitized, $path, $result.target)[0]
  }
}
