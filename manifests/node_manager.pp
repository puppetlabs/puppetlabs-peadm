# This profile is not intended to be continously enforced on PE masters.
# Rather, it describes state to enforce as a boostrap action, preparing the
# Puppet Enterprise console with a sane default environment configuration.
# Importantly, this includes assigning nodes to an environment matching thier
# trusted.extensions.pp_environment value by default.
#
# This class will be applied during primary master bootstrap using e.g.
#
#     puppet apply \
#       --exec 'class { "pe_architecture::node_manager":
#                 environments => ["production", "staging", "development"],
#               }'
#
class pe_architecture::node_manager (
  String[1]        $default_environment = 'production',
  Array[String[1]] $environments        = ['production', 'pe_production'],
) {

  ##################################################
  # PE INFRASTRUCTURE GROUPS
  ##################################################

  node_group { 'PE Infrastructure Agent':
    rule   => ['and', ['~', ['trusted', 'extensions', 'pp_role'], '^pe_architecture::']],
  }

  node_group { 'PE Master':
    rule   => ['or',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_architecture::primary_master'],
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_architecture::compile_master'],
    ],
  }

  node_group { 'PE PuppetDB':
    rule   => ['or',
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_architecture::primary_master'],
      ['=', ['trusted', 'extensions', 'pp_role'], 'pe_architecture::compile_master'],
    ],
  }

  # This class has to be included here because puppet_enterprise is declared
  # in the console with parameters. It is therefore not possible to include
  # puppet_enterprise::profile::database in code without causing a conflict.
  node_group { 'PE Database':
    ensure               => present,
    parent               => 'PE Infrastructure',
    environment          => 'production',
    override_environment => false,
    rule                 => ['and', ['=', ['trusted', 'extensions', 'pp_role'], 'pe_architecture::puppetdb_database']],
    classes              => {
      'puppet_enterprise::profile::database' => { },
    },
  }

  ##################################################
  # ENVIRONMENT GROUPS
  ##################################################

  node_group { 'Default environment':
    ensure               => present,
    environment          => 'production',
    override_environment => true,
    parent               => 'All Nodes',
    rule                 => ['and', ['~', 'name', '.*']],
  }

  node_group { 'agent-specified environment':
    ensure               => present,
    description          => 'This environment group exists for unusual testing and development only. Expect it to be empty',
    environment          => 'agent-specified',
    override_environment => true,
    parent               => 'Default environment',
    rule                 => [ ],
  }

  $environments.each |$env| {
    node_group { "${env} environment":
      ensure               => present,
      environment          => $env,
      override_environment => true,
      parent               => 'Default environment',
      rule                 => ['and', ['=', ['trusted', 'extensions', 'pp_environment'], $env]],
    }

    node_group { "${env} temp assignment":
      ensure               => present,
      description          => "Allow ${env} nodes to use a different Puppet environment temporarily",
      environment          => 'agent-specified',
      override_environment => true,
      parent               => "${env} environment",
    }
  }

}
