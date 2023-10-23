plan peadm::backup_ca(
  Peadm::SingleTargetSpec $target,
  Optional[String]                  $output_directory = '/tmp',
) {
  out::message('# Backing up ca and ssl certificates')
  # lint:ignore:strict_indent

  $timestamp = Timestamp.new().strftime('%Y-%m-%dT%H%M%SZ')
  $backup_directory = "${output_directory}/pe-backup-${timestamp}"

  # Create backup folder
  apply($target) {
    file { $backup_directory :
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => '0700',
    }
  }

  run_command(@("CMD"), $target)
    /opt/puppetlabs/bin/puppet-backup create --dir=${shellquote($backup_directory)} --name=ca_backup.tgz --scope=certs
    | CMD
  # lint:endignore
  return({ 'path' => "${backup_directory}/ca_backup.tgz" })
}
