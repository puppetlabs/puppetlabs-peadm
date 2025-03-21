# @api private
class peadm::setup::legacy_compiler_group (
  String[1] $primary_host,
  Optional[String] $internal_compiler_a_pool_address = undef,
  Optional[String] $internal_compiler_b_pool_address = undef,
) {
  Node_group {
    purge_behavior => none,
  }

  node_group { 'PE Legacy Compiler':
    ensure         => 'present',
    parent         => 'PE Master',
    purge_behavior => 'rule',
    rule           => ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
    classes        => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_a_pool_address, $internal_compiler_b_pool_address].filter |$_| { $_ },
        'puppetdb_port' => [8081],
      },
    },
  }

  node_group { 'PE Legacy Compiler Group A':
    ensure         => 'present',
    parent         => 'PE Legacy Compiler',
    purge_behavior => 'rule',
    rule           => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'A'],
    ],
    classes        => {
      'puppet_enterprise::profile::master' => {
        'puppetdb_host' => [$internal_compiler_b_pool_address, $internal_compiler_a_pool_address].filter |$_| { $_ },
        'puppetdb_port' => [8081],
      },
    },
    data           => {
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  node_group { 'PE Legacy Compiler Group B':
    ensure         => 'present',
    parent         => 'PE Legacy Compiler',
    purge_behavior => 'rule',
    rule           => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'B'],
    ],
    classes        => {
      'puppet_enterprise::profile::master' => {
        'puppetdb_host' => [$internal_compiler_a_pool_address, $internal_compiler_b_pool_address].filter |$_| { $_ },
        'puppetdb_port' => [8081],
      },
    },
    data           => {
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  node_group { 'PE Compiler':
    parent         => 'PE Master',
    purge_behavior => 'rule',
    rule           => ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
  }
}
