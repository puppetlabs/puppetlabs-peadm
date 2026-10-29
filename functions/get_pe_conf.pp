function peadm::get_pe_conf(Target $target) {
  # pe.conf holds console_admin_password, so read it as Sensitive (PE-47523)
  $current_pe_conf_content = peadm::read_sensitive_file($target, '/etc/puppetlabs/enterprise/conf.d/pe.conf')

  # Parse the current pe.conf content and return the hash
  return $current_pe_conf_content ? {
    undef   => {},
    default => stdlib::parsehocon($current_pe_conf_content.unwrap),
  }
}
