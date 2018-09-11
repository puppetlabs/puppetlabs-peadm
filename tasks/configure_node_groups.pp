#!/opt/puppetlabs/bin/puppet apply 
function param($name) { inline_template("<%= ENV['PT_${name}'] %>") }

class configure_node_groups (
  String[1]                        $primary_master_host            = param('primary_master_host'),
  String[1]                        $primary_master_replica_host    = param('primary_master_replica_host'),
  String[1]                        $puppetdb_database_host         = param('puppetdb_database_host'),
  String[1]                        $puppetdb_database_replica_host = param('puppetdb_database_replica_host'),
  String[1]                        $compile_master_pool_address    = param('compile_master_pool_address'),
  Pattern[/\A[a-z0-9_]+\Z/]        $default_environment            = 'production',
  Array[Pattern[/\A[a-z0-9_]+\Z/]] $environments                   = ['production'],
) {

  ##################################################
  # PE INFRASTRUCTURE GROUPS
  ##################################################

  node_group { 'PE Infrastructure Agent':
    rule => ['and', ['~', ['trusted', 'extensions', 'pp_role'], '^pe_xl::']],
  }

  node_group { 'PE Master':
    rule => ['or',
      ['and', ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master']],
      ['=', 'name', $primary_master_host],
    ],
    data => {
      'pe_repo' => { 'compile_master_pool_address' => $compile_master_pool_address },
    },
  }

  node_group { 'PE Compile Master Group A':
    ensure  => 'present',
    parent  => 'PE Master',
    rule    => ['and',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master'],
      ['=', ['trusted', 'extensions', 'pp_cluster'], 'A'],
    ], 
    classes => {
      'puppet_enterprise::profile::puppetdb' => { },
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => ['${clientcert}', $primary_master_host],
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
      'puppet_enterprise::profile::puppetdb' => { },
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => ['${clientcert}', $primary_master_replica_host],
        'puppetdb_port' => [8081],
      }
    },
  }

  node_group { 'PE HA Master':
    ensure => present,
    parent => 'PE Master',
    data   => {
      'puppet_enterprise::profile::primary_master_replica' => {'database_host_puppetdb' => $puppetdb_database_replica_host }
    },
  }

  # Do not manage the PuppetDB group. It causes problems regarding duplicate
  # resource definition errors.
  # node_group { 'PE PuppetDB':
  #   rule => ['or', ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master']],
  # }

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

include configure_node_groups
