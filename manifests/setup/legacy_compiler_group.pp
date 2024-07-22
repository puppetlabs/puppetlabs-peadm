# @api private
class peadm::setup::legacy_compiler_group (
  String[1] $primary_host
) {
  Node_group {
    purge_behavior => none,
  }

  node_group { 'PE Legacy Compiler':
    parent    => 'PE Master',
    rule      => ['and',
      ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'true'],
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
    ],
    classes   => {
      'pe_repo'                            => {},
      'puppet_enterprise::profile::master' => { 'code_manager_auto_configure' => true, 'replication_mode' => 'none' },
    },
    data      => {
      'pe_repo' => { 'compile_master_pool_address' => $primary_host },
    },
    variables => {
      'pe_master' => true,
    },
  }

  node_group { 'PE Legacy Compiler Group A':
    ensure => 'present',
    parent => 'PE Legacy Compiler',
    rule   => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'A'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'true'],
    ],
  }

  node_group { 'PE Legacy Compiler Group B':
    ensure => 'present',
    parent => 'PE Legacy Compiler',
    rule   => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'B'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'true'],
    ],
  }

  node_group { 'PE Compiler':
    rule   => ['and', ['=', ['trusted', 'extensions', peadm::oid('peadm_legacy_compiler')], 'false']],
  }
}
