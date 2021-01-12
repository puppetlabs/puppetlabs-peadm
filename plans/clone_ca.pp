plan peadm::util::clone_ca (
  Peadm::SingleTargetSpec $source_ca_host,
  Peadm::SingleTargetSpec $destination_ca_host,
) {
  $src_target = peadm::get_targets($source_ca_host, 1)
  $dst_target = peadm::get_targets($destination_ca_host, 1)

  # TODO:
  # Validate that the destination system does not yet have PE installed

  run_command('umask 022 && mkdir -p /etc/puppetlabs/puppet/ssl', $dst_target)
  run_command('tar -C /etc/puppetlabs/puppet/ssl -czf ca.tar.gz ca', $src_target)
  $download = download_file('/etc/puppetlabs/puppet/ssl/ca.tar.gz', 'downloads', $src_target)
  upload_file($download[0]['path'], '/etc/puppetlabs/puppet/ssl/ca.tar.gz', $dst_target)
  run_command('umask 022 && tar -C /etc/puppetlabs/puppet/ssl -xzf ca.tar.gz', $dst_target)

  # TODO:
  # increment the serial number file on the new system to prevent conflicts
  #run_command('increment serial file', $dst_target)

  run_command('rm /etc/puppetlabs/puppet/ssl/ca.tar.gz', [$src_target, $dst_target])

  # TODO
  # Clean up the ca tarball from the local Bolt host
  # rm downloads/${download[0]['path']}
}
