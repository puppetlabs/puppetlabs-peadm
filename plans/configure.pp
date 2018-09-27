plan pe_xl::configure (
  String[1]           $primary_master_host,
  String[1]           $puppetdb_database_host,
  String[1]           $primary_master_replica_host,
  String[1]           $puppetdb_database_replica_host,
  Array[String[1]]    $compile_master_hosts = [ ],

  # This parameter exists primarily to enable the use case of running
  # pe_xl::configure over the PCP transport. An orchestrator restart happens
  # during provision replica. Running `bolt plan run` directly on the primary
  # master and using local transport for that node will let the plan to run to
  # completion without failing due to being disconnected from the orchestrator.
  Boolean             $executing_on_primary_master = false,

  String[1]           $compile_master_pool_address = $primary_master_host,
  Boolean             $manage_environment_groups = true,
  String[1]           $token_file = '${HOME}/.puppetlabs/token',
  Optional[String[1]] $deploy_environment = undef,

  String[1]           $stagingdir = '/tmp',
) {

  # Allow for the configure task to be run local to the primary master.
  $primary_master_target = $executing_on_primary_master ? {
    true  => "local://${primary_master_host}",
    false => $primary_master_host,
  }

  # Retrieve and deploy Puppet modules from the Forge so that they can be used
  # for ensuring some configuration (node groups)
  pe_xl::install_module($primary_master_target, 'WhatsARanjit-node_manager', '0.7.1', $stagingdir)
  pe_xl::install_module($primary_master_target, 'puppetlabs-stdlib', '5.0.0', $stagingdir)

  # Set up the console node groups to configure the various hosts in their
  # roles
  run_task('pe_xl::configure_node_groups', $primary_master_target,
    primary_master_host            => $primary_master_host,
    primary_master_replica_host    => $primary_master_replica_host,
    puppetdb_database_host         => $puppetdb_database_host,
    puppetdb_database_replica_host => $puppetdb_database_replica_host,
    compile_master_pool_address    => $compile_master_pool_address,
    manage_environment_groups      => $manage_environment_groups,
  )

  # Run Puppet in no-op on the compile masters so that their status in PuppetDB
  # is updated and they can be identified by the puppet_enterprise module as
  # CMs
  run_task('pe_xl::puppet_runonce', [$compile_master_hosts, $primary_master_replica_host],
    noop => true,
  )

  # Run Puppet on the PuppetDB Database hosts to update their auth
  # configuration to allow the compile masters to connect
  run_task('pe_xl::puppet_runonce', [
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
  ])

  # Run Puppet on the primary master to ensure all services configured and
  # running in prep for provisioning the replica. This is done separately so
  # that a service restart of pe-puppetserver doesn't cause Puppet runs on
  # other nodes to fail.
  run_task('pe_xl::puppet_runonce', $primary_master_target)

  # Run the PE Replica Provision
  run_task('pe_xl::provision_replica', $primary_master_target,
    primary_master_replica => $primary_master_replica_host,
    token_file => $token_file,
  )

  # Run the PE Replica Enable
  run_task('pe_xl::enable_replica', $primary_master_target,
    primary_master_replica => $primary_master_replica_host,
    token_file => $token_file,
  )

  # Run Puppet everywhere to pick up last remaining config tweaks
  run_task('pe_xl::puppet_runonce', [
    $primary_master_target, $primary_master_replica_host,
    $puppetdb_database_host, $puppetdb_database_replica_host,
    $compile_master_hosts,
  ].pe_xl::flatten_compact())

  # Deploy an environment if a deploy environment is specified
  if $deploy_environment {
    run_task('pe_xl::code_manager', $primary_master_target,
      action => "deploy ${deploy_environment}",
    )
  }

  return('Configuration of Puppet Enterprise with replica succeeded.')
}
