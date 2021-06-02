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
