plan pe_xl::configure (

  String[1]           $version = '2018.1.3',
  String[1]           $console_password,
  Hash                $r10k_sources = { },

  String[1]           $primary_master_host,
  String[1]           $puppetdb_database_host,
  Array[String[1]]    $compile_master_hosts = [ ],
  Array[String[1]]    $dns_alt_names = [ ],

  String[1]           $primary_master_replica_host = undef,
  String[1]           $puppetdb_database_replica_host = undef,

  String[1]           $compile_master_pool_address = $primary_master_host,
  Optional[String[1]] $load_balancer_host = undef,

  String[1]           $stagingdir = '/tmp',
) {

  # Retrieve and deploy Puppet modules from the Forge so that they can be used
  # for ensuring some configuration (node groups)
  pe_xl::install_module($primary_master_host, 'WhatsARanjit-node_manager', '0.7.1')
  pe_xl::install_module($primary_master_host, 'puppetlabs-stdlib', '5.0.0')

  # Set up the console node groups to configure the various hosts in their
  # roles
  run_task('pe_xl::configure_node_groups', $primary_master_host,
    primary_master_host            => $primary_master_host,
    primary_master_replica_host    => $primary_master_replica_host,
    puppetdb_database_host         => $puppetdb_database_host,
    puppetdb_database_replica_host => $puppetdb_database_replica_host,
    compile_master_pool_address    => $compile_master_pool_address,
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

  # Run Puppet in normal mode on compile master hosts to finish configuration
  run_task('pe_xl::puppet_runonce', [
    $primary_master_host,
    $compile_master_hosts,
  ])

  # Run the PE Replica Provision
  run_task('pe_xl::provision_replica', $primary_master_host,
    primary_master_replica => $primary_master_replica_host,
  )

  # Run the PE Replica Enable
  run_task('pe_xl::enable_replica', $primary_master_host,
    primary_master_replica => $primary_master_replica_host,
  )

  # Run Puppet everywhere to pick up last remaining config tweaks
  run_task('pe_xl::puppet_runonce', [
    $primary_master_host,    $primary_master_replica_host,
    $puppetdb_database_host, $puppetdb_database_replica_host,
    $compile_master_hosts,   $load_balancer_host,
  ].pe_xl::flatten_compact())

  return('Configuration of Puppet Enterprise with replica succeeded.')
}
