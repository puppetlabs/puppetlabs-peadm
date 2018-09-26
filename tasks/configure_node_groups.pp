#!/opt/puppetlabs/bin/puppet apply 
function param($name) { inline_template("<%= ENV['PT_${name}'] %>") }

class configure_node_groups (
  String[1]                        $primary_master_host            = param('primary_master_host'),
  String[1]                        $primary_master_replica_host    = param('primary_master_replica_host'),
  String[1]                        $puppetdb_database_host         = param('puppetdb_database_host'),
  String[1]                        $puppetdb_database_replica_host = param('puppetdb_database_replica_host'),
  String[1]                        $compile_master_pool_address    = param('compile_master_pool_address'),
  Boolean                          $manage_environment_groups      = true,
  Pattern[/\A[a-z0-9_]+\Z/]        $default_environment            = 'production',
  Array[Pattern[/\A[a-z0-9_]+\Z/]] $environments                   = ['production'],
) {

  ##################################################
  # PE INFRASTRUCTURE GROUPS
  ##################################################

  # We modify this group's rule such that all PE infrastructure nodes will be
  # members.
  node_group { 'PE Infrastructure Agent':
    rule => ['and', ['~', ['trusted', 'extensions', 'pp_role'], '^pe_xl::']],
  }

  # We modify this group to add, as data, the compile_master_pool_address only.
  # Because the group does not have any data by default this does not impact
  # out-of-box configuration of the group.
  node_group { 'PE Master':
    rule => ['or',
      ['and', ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master']],
      ['=', 'name', $primary_master_host],
    ],
    data => {
      'pe_repo' => { 'compile_master_pool_address' => $compile_master_pool_address },
    },
  }

  # We need to pre-create this group so that the primary master replica can be
  # identified as running PuppetDB, so that Puppet will create a pg_ident
  # authorization rule for it on the PostgreSQL nodes.
  node_group { 'PE HA Replica':
    ensure  => 'present',
    parent  => 'PE Infrastructure',
    rule => ['or', ['=', 'name', $primary_master_replica_host]],
    classes => {
      'puppet_enterprise::profile::primary_master_replica' => { }
    },
  }

  # Create data-only groups to store PuppetDB PostgreSQL database configuration
  # information specific to the primary master and primary master replica nodes.
  node_group { 'PE Master A':
    ensure  => present,
    parent  => 'PE Infrastructure',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::primary_master'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'A'],
    ], 
    data => {
      'puppet_enterprise::profile::primary_master_replica' => {
        'database_host_puppetdb' => $puppetdb_database_host,
      },
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $puppetdb_database_host,
      },
    },
  }

  node_group { 'PE Master B':
    ensure  => present,
    parent  => 'PE Infrastructure',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::primary_master'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'B'],
    ], 
    data => {
      'puppet_enterprise::profile::primary_master_replica' => {
        'database_host_puppetdb' => $puppetdb_database_replica_host,
      },
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $puppetdb_database_replica_host,
      },
    },
  }

  # Configure the compile masters for HA, grouped into two pools, each pool
  # having an affinity for one "availability zone" or the other. Even with an
  # affinity, note that data from each compile master is replicated to both
  # "availability zones".
  node_group { 'PE Compile Master Group A':
    ensure  => 'present',
    parent  => 'PE Master',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'A'],
    ], 
    classes => {
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $puppetdb_database_host,
      },
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => ['${clientcert}', $primary_master_replica_host],
        'puppetdb_port' => [8081],
      }
    },
  }

  node_group { 'PE Compile Master Group B':
    ensure  => 'present',
    parent  => 'PE Master',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'B'],
    ], 
    classes => {
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $puppetdb_database_replica_host,
      },
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => ['${clientcert}', $primary_master_host],
        'puppetdb_port' => [8081],
      }
    },
  }

  # This class has to be included here because puppet_enterprise is declared
  # in the console with parameters. It is therefore not possible to include
  # puppet_enterprise::profile::database in code without causing a conflict.
  node_group { 'PE Database':
    ensure               => present,
    parent               => 'PE Infrastructure',
    environment          => 'production',
    override_environment => false,
    rule                 => ['and', ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::puppetdb_database']],
    classes              => {
      'puppet_enterprise::profile::database' => { },
    },
  }

  if str2bool("$manage_environment_groups") {
    ##################################################
    # ENVIRONMENT GROUPS
    ##################################################
  
    node_group { 'All Environments':
      ensure               => present,
      description          => 'Environment group parent and default',
      environment          => $default_environment,
      override_environment => true,
      parent               => 'All Nodes',
      rule                 => ['and', ['~', 'name', '.*']],
    }
  
    node_group { 'Agent-specified environment':
      ensure               => present,
      description          => 'This environment group exists for unusual testing and development only. Expect it to be empty',
      environment          => 'agent-specified',
      override_environment => true,
      parent               => 'All Environments',
      rule                 => [ ],
    }
  
    $environments.each |$env| {
      $title_env = capitalize($env)
  
      node_group { "${title_env} environment":
        ensure               => present,
        environment          => $env,
        override_environment => true,
        parent               => 'All Environments',
        rule                 => ['and', ['=', ['trusted', 'extensions', 'pp_environment'], $env]],
      }
  
      node_group { "${title_env} one-time run exception":
        ensure               => present,
        description          => "Allow ${env} nodes to request a different puppet environment for a one-time run",
        environment          => 'agent-specified',
        override_environment => true,
        parent               => "${title_env} environment",
        rule                 => ['and', ['~', ['fact', 'agent_specified_environment'], '.+']],
      }
    }
  
  }
}  
include configure_node_groups
