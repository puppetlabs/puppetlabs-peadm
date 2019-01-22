# This profile is not intended to be continously enforced on PE masters.
# Rather, it describes state to enforce as a boostrap action, preparing the
# Puppet Enterprise console with a sane default environment configuration.
# Importantly, this includes assigning nodes to an environment matching thier
# trusted.extensions.pp_environment value by default.
#
# This class will be applied during master bootstrap using e.g.
#
#     puppet apply \
#       --exec 'class { "pe_xl::node_manager":
#                 environments => ["production", "staging", "development"],
#               }'
#
class pe_xl::node_manager (
  String[1]                        $master_host,
  String[1]                        $master_replica_host,
  String[1]                        $puppetdb_database_host,
  String[1]                        $puppetdb_database_replica_host,
  String[1]                        $compiler_pool_address,
  Boolean                          $manage_environment_groups = true,
  Pattern[/\A[a-z0-9_]+\Z/]        $default_environment       = 'production',
  Array[Pattern[/\A[a-z0-9_]+\Z/]] $environments              = ['production'],
) {

  ##################################################
  # PE INFRASTRUCTURE GROUPS
  ##################################################

  # We modify this group's rule such that all PE infrastructure nodes will be
  # members.
  node_group { 'PE Infrastructure Agent':
    rule => ['and', ['~', ['trusted', 'extensions', 'pp_role'], '^pe_xl::']],
  }

  # We modify this group to add, as data, the compiler_pool_address only.
  # Because the group does not have any data by default this does not impact
  # out-of-box configuration of the group.
  node_group { 'PE Master':
    parent  => 'PE Infrastructure',
    rule    => ['or',
      ['and', ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compiler']],
      ['=', 'name', $master_host],
    ],
    data    => {
      'pe_repo' => { 'compile_master_pool_address' => $compiler_pool_address },
    },
  }

  # We need to pre-create this group so that the master replica can be
  # identified as running PuppetDB, so that Puppet will create a pg_ident
  # authorization rule for it on the PostgreSQL nodes.
  node_group { 'PE HA Replica':
    ensure  => 'present',
    parent  => 'PE Infrastructure',
    rule => ['or', ['=', 'name', $master_replica_host]],
    classes => {
      'puppet_enterprise::profile::primary_master_replica' => { }
    },
    variables => { "pe_xl_replica" => true },
  }

  # Create data-only groups to store PuppetDB PostgreSQL database configuration
  # information specific to the master and master replica nodes.
  node_group { 'PE Master A':
    ensure  => present,
    parent  => 'PE Infrastructure',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::master'],
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
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::master'],
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

  # Hiera data tuning for compilers
  $compiler_data = {
    'puppet_enterprise::profile::puppetdb' => {
      'gc_interval' => '0',
    },
    'puppet_enterprise::puppetdb' => {
      'command_processing_threads' => 2,
      'write_maximum_pool_size'    => 4,
      'read_maximum_pool_size'     => 10,
    },
  }

  # Configure the compilers for HA, grouped into two pools, each pool
  # having an affinity for one "availability zone" or the other. Even with an
  # affinity, note that data from each compiler is replicated to both
  # "availability zones".
  node_group { 'PE Compiler Group A':
    ensure  => 'present',
    parent  => 'PE Master',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compiler'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'A'],
    ], 
    classes => {
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $puppetdb_database_host,
      },
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => ['${clientcert}', $master_replica_host],
        'puppetdb_port' => [8081],
      }
    },
    data    => $compiler_data,
  }

  node_group { 'PE Compiler Group B':
    ensure  => 'present',
    parent  => 'PE Master',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compiler'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'B'],
    ], 
    classes => {
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $puppetdb_database_replica_host,
      },
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => ['${clientcert}', $master_host],
        'puppetdb_port' => [8081],
      }
    },
    data    => $compiler_data,
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


  if ($manage_environment_groups == 'true') {

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
