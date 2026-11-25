plan peadm::backup_ca(
  Peadm::SingleTargetSpec $target,
  Optional[Stdlib::Unixpath]        $output_directory = '/tmp',
) {
  # lint:ignore:strict_indent

  $timestamp = Timestamp.new().strftime('%Y-%m-%dT%H%M%SZ')
  $backup_directory = "${output_directory}/pe-backup-${timestamp}"

  # Create the backup folder. With a database-backed CA, puppet-backup stages
  # the pe-ca dump as the pe-postgres user, which cannot enter a root-only
  # (0700) folder, so the folder is 0711, the same mode peadm::backup uses. mkdir without -p fails
  # if the folder already exists, so a folder planted at this predictable path
  # is never reused. It also fails if output_directory does not exist.
  # (PE-48629)
  run_command("mkdir -m 0711 ${shellquote($backup_directory)}", $target)

  # With a database-backed CA (bootstrap.cfg loads database-storage-service,
  # e.g. PE 2025.12.2, 2026.0.1, 2026.0.2), the CA files on disk ($cadir:
  # signed certificates, serial) only advance when the CA is exported. The
  # certs scope archives those files together with a dump of the pe-ca
  # database (pe-ca.bin); without an export first, the archived files miss
  # certificates signed since the last export and hold a stale serial. Export
  # first so the archived files match the database, as peadm::backup does.
  # (PE-48629)
  $ca_backend = run_command(@("CMD"/L), $target).first['stdout'].chomp
    grep -v '^[[:space:]]*#' /etc/puppetlabs/puppetserver/bootstrap.cfg \
      | grep -q '^[[:space:]]*puppetlabs.services.ca.database-storage-service/' \
      && echo database || echo filesystem
    | CMD
  if $ca_backend == 'database' {
    out::message('# Exporting CA database to disk before backing up certs')
    run_command('/opt/puppetlabs/bin/puppetserver ca storage --export', $target)
  }

  # The archive holds the CA private key. puppet-backup creates it with the
  # process umask, and the folder is traversable (0711) with a fixed archive
  # name, so umask 0077 keeps the archive readable by root only. (PE-48629)
  out::message('# Backing up ca and ssl certificates')
  run_command(@("CMD"), $target)
    umask 0077 && /opt/puppetlabs/bin/puppet-backup create --dir=${shellquote($backup_directory)} --name=ca_backup.tgz --scope=certs
    | CMD
  # lint:endignore
  return({ 'path' => "${backup_directory}/ca_backup.tgz" })
}
