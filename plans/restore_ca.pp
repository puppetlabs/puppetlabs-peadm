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
