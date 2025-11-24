#
# @summary check if a custom PE environment is set in pe.conf
#
# @param primary the FQDN for the primary, here we will read the pe.conf from
#
# @return [String] the desired environment for PE specific node groups
#
# @see https://www.puppet.com/docs/pe/latest/upgrade_pe#update_environment
#
# @author Tim Meusel <tim@bastelfreak.de>
#
function peadm::get_node_group_environment(Peadm::SingleTargetSpec $primary) {
  $peconf = peadm::get_pe_conf(get_target($primary))
  # if both are set, they need to be set to the same value
  # if they are not set, we assume that the user runs their infra in production
  $pe_install = $peconf['pe_install::install::classification::pe_node_group_environment']
  $puppet_enterprise = $peconf['puppet_enterprise::master::recover_configuration::pe_environment']

  # check if both are equal
  # This also evaluates to true if both are undef
  if $pe_install == $puppet_enterprise {
    # check if the option isn't undef
    # ToDo: A proper regex for allowed characters in an environment would be nice
    # https://github.com/puppetlabs/puppet-docs/issues/1158
    if $pe_install =~ String[1] {
      return $pe_install
    } else {
      return 'production'
    }
  } else {
    fail("pe_install::install::classification::pe_node_group_environment and puppet_enterprise::master::recover_configuration::pe_environment need to be set to the same value, not '${pe_install}' and '${puppet_enterprise}'")
  }
}
