# @api private
class peadm::setup::legacy_compiler_group (
  String[1] $primary_host,
  Optional[String]                  $internal_compiler_a_pool_address = undef,
  Optional[String]                  $internal_compiler_b_pool_address = undef,
) {
  Node_group {
    purge_behavior => none,
  }

  node_group { 'PE Legacy Compiler':
    parent  => 'PE Master',
    rule    => ['and',
      ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'true'],
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
    ],
    classes => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_a_pool_address, $internal_compiler_b_pool_address].filter |$_| { $_ },
        'puppetdb_port' => [8081],
      },
    },
  }

  node_group { 'PE Legacy Compiler Group A':
    ensure  => 'present',
    parent  => 'PE Legacy Compiler',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'A'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'true'],
    ],
    classes => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_b_pool_address, $internal_compiler_a_pool_address].filter |$_| { $_ },
        'puppetdb_port' => [8081],
      },
    },
    data    => {
      # Workaround for GH-118
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  node_group { 'PE Legacy Compiler Group B':
    ensure  => 'present',
    parent  => 'PE Legacy Compiler',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'B'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'true'],
    ],
    classes => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_a_pool_address, $internal_compiler_b_pool_address].filter |$_| { $_ },
        'puppetdb_port' => [8081],
      },
    },
    data    => {
      # Workaround for GH-118
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  node_group { 'PE Compiler':
    rule   => ['and', ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'false']],
  }
}
