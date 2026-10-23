# @summary Restore the certificate authority and SSL certificates
# @param target The primary target on which to restore certificates.
# @param file_path Path to the certificate backup archive on the target.
# @param recovery_directory Temporary directory on the target for extracting the backup.
plan peadm::restore_ca(
  Peadm::SingleTargetSpec $target,
  String                  $file_path,
  Optional[String]        $recovery_directory = '/tmp/peadm_recovery',
) {
  out::message('# Restoring ca and ssl certificates')

  # lint:ignore:strict_indent
  run_command(@("CMD"/L), $target)
        /opt/puppetlabs/bin/puppet-backup restore \
    --scope=certs \
    --tempdir=${shellquote($recovery_directory)} \
    --force \
    ${shellquote($file_path)}
  | CMD
}
