# @api private
plan peadm::util::sanitize_pg_pe_conf (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $primary_host,
) {
  $primary_target = get_target($primary_host)

  $path = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
  # Ensure the pe.conf file on PostgreSQL nodes has the needed values for
  # puppet_primary_host and database_host
  get_targets($targets).map |$target| {
    # This file can hold console_admin_password and whatever else the operator
    # gave the installer, so read it as Sensitive and don't print it (PE-47523)
    $content = peadm::read_sensitive_file($target, $path)
    if $content == undef {
      fail_plan("No pe.conf at ${path} on ${target.name}")
    }

    # On a cluster PEADM didn't build this is the installer's HOCON, which
    # parsejson can't read, and its parse error quotes the whole file. The
    # default stops parsehocon raising an error that quotes it too. (stdlib may
    # still log that error at debug level.)
    $parsed = stdlib::parsehocon($content.unwrap, 'unparseable')
    if $parsed =~ String {
      fail_plan("The pe.conf on ${target.name} could not be parsed")
    }

    out::message("Sanitizing pe.conf on ${target.name}")
    $sanitized = $parsed + {
      'puppet_enterprise::puppet_master_host' => $primary_target.peadm::certname(),
      'puppet_enterprise::puppetdb_database_host'      => $target.peadm::certname(),
    }

    # Return the result of file_content_upload. There is only one target
    peadm::file_content_upload(stdlib::to_json_pretty($sanitized), $path, $target)[0]
  }
}
