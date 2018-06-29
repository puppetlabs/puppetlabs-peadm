#!/opt/puppetlabs/bin/puppet apply

$default_environment = 'production',
$environments        = ['production'],

##################################################
# PE INFRASTRUCTURE GROUPS
##################################################

node_group { 'PE Infrastructure Agent':
  rule   => ['and', ['=', ['trusted', 'extensions', 'pp_application'], 'puppet']],
}

node_group { 'PE Master':
  rule   => ['or',
    ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::primary_master'],
    ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master'],
  ],
}

node_group { 'PE PuppetDB':
  rule   => ['or',
    ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::primary_master'],
    ['=', ['trusted', 'extensions', 'pp_role'], 'pe_xl::compile_master'],
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
