# @api private
# @summary Used during the peadm::convert plan
#
# TODO: This class should be moved to puppet-enterprise-modules
# See: https://github.com/puppetlabs/puppet-enterprise-modules/tree/main/modules
#
class peadm::setup::convert_node_manager {
  require peadm::setup::node_manager

  # These two groups were renamed in peadm 3.x, but may have existed if a
  # cluster is being converted from peadm 2.x or earlier. Ensure that they are
  # absent, once the new groups are present.

  node_group { 'PE Master A':
    ensure => absent,
  }

  node_group { 'PE Master B':
    ensure => absent,
  }
}
