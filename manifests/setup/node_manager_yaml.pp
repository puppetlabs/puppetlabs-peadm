# @api private
# @summary Set up the node_manager.yaml file in the temporary Bolt confdir
#
# This configuration permits node_group resources to be used during Bolt apply
# runs. It is necessary to do it this way because node_manager requires a
# configuration file, located in $confdir. But, when Bolt applies a catalog, it
# does so using a unique, dynamic $confdir.
class peadm::setup::node_manager_yaml (
  String $primary_host
) {
  # Necessary to give the sandboxed Puppet executor the configuration
  # necessary to connect to the classifier`
  file { 'node_manager.yaml':
    ensure  => file,
    mode    => '0644',
    path    => Deferred('peadm::node_manager_yaml_location'),
    content => epp('peadm/node_manager.yaml.epp', {
        server => $primary_host,
    }),
  }
}
