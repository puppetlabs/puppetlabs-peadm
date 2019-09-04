# @summary Upgrade an Extra Large stack from one .z to the next
#
plan pe_xl::upgrade (
  String[1] $master_host,
  String[1] $puppetdb_database_host,
  Optional[String[1]] $master_replica_host = undef,
  Optional[String[1]] $puppetdb_database_replica_host = undef,

  String[1] $version,

  # This parameter exists to enable the use case of running pe_xl::upgrade over
  # the PCP transport. An orchestrator restart happens during provision
  # replica. Running `bolt plan run` directly on the master and using local
  # transport for that node will let the plan to run to completion without
  # failing due to being disconnected from the orchestrator.
  Boolean $executing_on_master = false,

  String[1] $stagingdir = '/tmp',
  String[1] $pe_source  = "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
) {

  # Allow for the upgrade task to be run local to the master.
  $master_target = $executing_on_master ? {
    true  => "local://${master_host}",
    false => $master_host,
  }

  $ha_replica_target = [
    $master_replica_host,
  ].pe_xl::flatten_compact()

  $ha_database_target = [
    $puppetdb_database_replica_host,
  ].pe_xl::flatten_compact()

  # Look up which hosts are compilers in the stack
  # We look up groups of CMs separately since when they are upgraded is determined
  # by which PDB PG host they are affiliated with
  $compiler_cluster_master_hosts = puppetdb_query(@("PQL")).map |$node| { $node['certname'] }
    resources[certname] { 
      type = "Class" and
      title = "Puppet_enterprise::Profile::Puppetdb" and
      parameters.database_host = "${puppetdb_database_host}" and
      !(certname = "${master_host}") }
    | PQL

  $compiler_cluster_master_replica_hosts = puppetdb_query(@("PQL")).map |$node| { $node['certname'] }
    resources[certname] { 
      type = "Class" and
      title = "Puppet_enterprise::Profile::Puppetdb" and
      parameters.database_host = "${puppetdb_database_replica_host}" and
      !(certname = "${master_replica_host}") }
    | PQL

  $all_hosts = [
    $master_target,
    $puppetdb_database_host,
    $master_replica_host,
    $puppetdb_database_replica_host,
    $compiler_cluster_master_hosts,
    $compiler_cluster_master_replica_hosts,
  ].pe_xl::flatten_compact()

  # We need to make sure we aren't using PCP as this will go down during the upgrade
  $all_hosts.pe_xl::fail_on_transport('pcp')

  # TODO: Do we need to update the pe.conf(s) with a console password?

  # Download the PE tarball on the nodes that need it
  $upload_tarball_path = "/tmp/puppet-enterprise-${version}-el-7-x86_64.tar.gz"

  $download_hosts = [
    $master_target,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
  ].pe_xl::flatten_compact()

  run_task('pe_xl::download', $download_hosts,
    source => $pe_source,
    path   => $upload_tarball_path,
  )

  # Shut down Puppet on all infra hosts
  run_task('service', $all_hosts,
    action => 'stop',
    name   => 'puppet',
  )

  # Shut down PuppetDB on CMs that use the PM's PDB PG
  run_task('service', $compiler_cluster_master_hosts,
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  # Shut down pe-* services on the master. Only shutting down the ones
  # that have failover pairs on the master replica.
  ['pe-console-services', 'pe-nginx', 'pe-puppetserver', 'pe-puppetdb', 'pe-postgresql'].each |$service| {
    run_task('service', $master_target,
      action => 'stop',
      name   => $service,
    )
  }

  # TODO: Firewall up the master

  run_task('pe_xl::pe_install', $master_target,
    tarball => $upload_tarball_path,
  )

  # Upgrade the master PuppetDB PostgreSQL host. Note that installer-driven
  # upgrade will de-configure auth access for compilers. Re-run Puppet
  # immediately to fully re-enable
  run_task('pe_xl::pe_install', $puppetdb_database_host,
    tarball => $upload_tarball_path,
  )
  run_task('pe_xl::puppet_runonce', $puppetdb_database_host)

  # Stop PuppetDB on the master
  run_task('service', $master_target,
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  # TODO: Unblock 8081 between the master and the master replica

  # Start PuppetDB on the master
  run_task('service', $master_target,
    action => 'start',
    name   => 'pe-puppetdb',
  )

  # TODO: Remove remaining firewall blocks

  # Wait until orchestrator service is healthy to proceed
  run_task('pe_xl::orchestrator_healthcheck', $master_target)

  # Upgrade the compiler group A hosts
  run_task('pe_xl::agent_upgrade', $compiler_cluster_master_hosts,
    server => $master_host,
  )

  # Shut down PuppetDB on CMs that use the PMR's PDB PG
  run_task('service', $compiler_cluster_master_replica_hosts,
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  # Run the upgrade.sh script on the master replica host
  run_task('pe_xl::agent_upgrade', $ha_replica_target,
    server => $master_host,
  )

  # Upgrade the master replica's PuppetDB PostgreSQL host
  run_task('pe_xl::pe_install', $ha_database_target,
    tarball => $upload_tarball_path,
  )
  run_task('pe_xl::puppet_runonce', $ha_database_target)

  # Upgrade the compiler group B hosts
  run_task('pe_xl::agent_upgrade', $compiler_cluster_master_replica_hosts,
    server => $master_host,
  )

  # Ensure Puppet running on all infrastructure hosts
  run_task('service', $all_hosts,
    action => 'start',
    name   => 'puppet',
  )

  return('End Plan')
}

