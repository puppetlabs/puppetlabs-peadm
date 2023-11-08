function peadm::get_pe_conf(Target $target) {
  $current_pe_conf_content = run_task('peadm::read_file', $target, path => '/etc/puppetlabs/enterprise/conf.d/pe.conf').first['content']

  # Parse the current pe.conf content and return the hash
  return $current_pe_conf_content ? {
    undef   => {},
    default => stdlib::parsehocon($current_pe_conf_content),
  }
}
