# @summary Configure first-time classification and HA setup
#
plan pe_xl::configure (
  String[1]           $master_host,
  String[1]           $puppetdb_database_host,
  String[1]           $master_replica_host,
  String[1]           $puppetdb_database_replica_host,
  Array[String[1]]    $compiler_hosts = [ ],

  # This parameter exists primarily to enable the use case of running
  # pe_xl::configure over the PCP transport. An orchestrator restart happens
  # during provision replica. Running `bolt plan run` directly on the master
  # and using local transport for that node will let the plan to run to
  # completion without failing due to being disconnected from the orchestrator.
  Boolean             $executing_on_master = false,

  String[1]           $compiler_pool_address = $master_host,
  Optional[String[1]] $token_file = undef,
  Optional[String[1]] $deploy_environment = undef,

  String[1]           $stagingdir = '/tmp',
) {

  # Allow for the configure task to be run local to the master.
  $master_target = $executing_on_master ? {
    true  => "local://${master_host}",
    false => $master_host,
  }

  # Retrieve and deploy Puppet modules from the Forge so that they can be used
  # for ensuring some configuration (node groups)
  [ ['WhatsARanjit-node_manager', '0.7.1'],
    ['puppetlabs-stdlib',         '5.0.0'],
  ].each |$tuple| {
    run_plan('pe_xl::util::install_module',
      nodes      => $master_target,
      module     => $tuple[0],
      version    => $tuple[1],
      stagingdir => $stagingdir,
    )
  }

  # Set up the console node groups to configure the various hosts in their
  # roles
  run_task('pe_xl::configure_node_groups', $master_target,
    master_host                    => $master_host,
    master_replica_host            => $master_replica_host,
    puppetdb_database_host         => $puppetdb_database_host,
    puppetdb_database_replica_host => $puppetdb_database_replica_host,
    compiler_pool_address          => $compiler_pool_address,
  )

  # Run Puppet in no-op on the compilers so that their status in PuppetDB
  # is updated and they can be identified by the puppet_enterprise module as
  # CMs
  run_task('pe_xl::puppet_runonce', [$compiler_hosts, $master_replica_host],
    noop => true,
  )

  # Run Puppet on the PuppetDB Database hosts to update their auth
  # configuration to allow the compilers to connect
  run_task('pe_xl::puppet_runonce', [
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
  ])

  # Run Puppet on the master to ensure all services configured and
  # running in prep for provisioning the replica. This is done separately so
  # that a service restart of pe-puppetserver doesn't cause Puppet runs on
  # other nodes to fail.
  run_task('pe_xl::puppet_runonce', $master_target)

  # Run the PE Replica Provision
  run_task('pe_xl::provision_replica', $master_target,
    master_replica         => $master_replica_host,
    token_file             => $token_file,
  )

  # Run the PE Replica Enable
  run_task('pe_xl::enable_replica', $master_target,
    master_replica         => $master_replica_host,
    token_file             => $token_file,
  )

  # Run Puppet everywhere to pick up last remaining config tweaks
  run_task('pe_xl::puppet_runonce', [
    $master_target, $master_replica_host,
    $puppetdb_database_host, $puppetdb_database_replica_host,
    $compiler_hosts,
  ].pe_xl::flatten_compact())

  # Deploy an environment if a deploy environment is specified
  if $deploy_environment {
    run_task('pe_xl::code_manager', $master_target,
      action => "deploy ${deploy_environment}",
    )
  }

  return('Configuration of Puppet Enterprise with replica succeeded.')
}
