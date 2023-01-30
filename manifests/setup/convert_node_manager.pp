# @api private
# @summary Used during the peadm::convert plan
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
