plan pe_xl::test (
  TargetSpec $nodes,
) {
  $target = get_target($nodes)

  $servername = $target.host
  apply($target) {

    file { 'node_manager.yaml':
      ensure  => file,
      mode    => '0644',
      path    => Deferred('pe_xl::node_manager_yaml_location'),
      content => epp('pe_xl/node_manager.yaml.epp', {
        server => $servername,
      }),
    }

    Node_group {
      require => File['node_manager.yaml'],
    }

    node_group { 'Test Group':
      ensure => present,
      parent => 'PE Infrastructure',
      rule   => ['and',
        ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::master'],
        ['=', ['trusted', 'extensions', 'pp_cluster'], 'B'],
      ],
    }

  }

}
