plan pe_xl::upgrade (
  String[1]        $primary_master_host,
  String[1]        $puppetdb_database_host,
  String[1]        $primary_master_replica_host,
  String[1]        $puppetdb_database_replica_host,

#  String[1]        $console_password,
  String[1]        $version = '2018.1.3',

  String[1]        $stagingdir = '/tmp',
  String[1]        $pe_source  = "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
) {

  # Look up which hosts are compile masters in the stack
  # We look up groups of CMs separately since when they are upgraded is determined
  # by which PDB PG host they are affiliated with
  $cm_cluster_primary_hosts = puppetdb_query(@("PQL")).map |$node| { $node['certname'] }
    resources[certname] { 
      type = "Class" and
      title = "Puppet_enterprise::Profile::Puppetdb" and
      parameters.database_host = "${puppetdb_database_host}" and
      !(certname = "$primary_master_host") }
    | PQL

  $cm_cluster_replica_hosts = puppetdb_query(@("PQL")).map |$node| { $node['certname'] }
    resources[certname] { 
      type = "Class" and
      title = "Puppet_enterprise::Profile::Puppetdb" and
      parameters.database_host = "${puppetdb_database_replica_host}" and
      !(certname = "$primary_master_replica_host") }
    | PQL

  $all_hosts = [
    $primary_master_host,
    $puppetdb_database_host,
    $primary_master_replica_host,
    $puppetdb_database_replica_host,
    $cm_cluster_primary_hosts,
    $cm_cluster_replica_hosts,
  ].pe_xl::flatten_compact()

  $primary_master_local = "local://$primary_master_host"

  # TODO: Do we need to update the pe.conf(s) with a console password?

  # Download the PE tarball on the nodes that need it
  $upload_tarball_path = "/tmp/puppet-enterprise-${version}-el-7-x86_64.tar.gz"

  run_task('pe_xl::download', [
      $primary_master_host,
      $puppetdb_database_host,
      $puppetdb_database_replica_host
    ],
    source => $pe_source,
    path   => $upload_tarball_path,
  )

  # Shut down Puppet on all infra hosts
  run_task('service', $all_hosts,
    action => 'stop',
    name   => 'puppet',
  )

  # Shut down PuppetDB on CMs that use the PM's PDB PG
  run_task('service', $cm_cluster_primary_hosts,
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  # Shut down pe-* services on the primary master. Only shutting down the ones
  # that have failover pairs on the replica.
  ['pe-console-services', 'pe-nginx', 'pe-puppetserver', 'pe-puppetdb', 'pe-postgresql'].each |$service| {
    run_task('service', $primary_master_local,
      action => 'stop',
      name   => $service,
    )
  }

  # TODO: Firewall up the primary master

  # Upgrade the primary master using the local:// transport in anticipation of
  # the orchestrator service being restarted during the upgrade.
  run_task('pe_xl::pe_install', $primary_master_local,
    tarball => $upload_tarball_path,
  )

  # Upgrade the primary PuppetDB PostgreSQL host. Note that installer-driven
  # upgrade will de-configure auth access for compile masters. Re-run Puppet
  # immediately to fully re-enable
  run_task('pe_xl::pe_install', $puppetdb_database_host,
    tarball => $upload_tarball_path,
  )
  run_task('pe_xl::puppet_runonce', $puppetdb_database_host)

  # Stop PuppetDB on the primary master
  run_task('service', $primary_master_local,
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  # TODO: Unblock 8081 between the primary master and the replica

  # Start PuppetDB on the primary master
  run_task('service', $primary_master_local,
    action => 'start',
    name   => 'pe-puppetdb',
  )

  # TODO: Remove remaining firewall blocks

  # Wait until orchestrator service is healthy to proceed
  run_task('pe_xl::orchestrator_healthcheck', $primary_master_local)

  # Upgrade the compile master group A hosts
  run_task('pe_xl::agent_upgrade', $cm_cluster_primary_hosts,
    server => $primary_master_host,
  )

  # Shut down PuppetDB on CMs that use the PMR's PDB PG
  run_task('service', $cm_cluster_replica_hosts,
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  # Run the upgrade.sh script on the primary master replica host
  run_task('pe_xl::agent_upgrade', $primary_master_replica_host,
    server => $primary_master_host,
  )

  # Upgrade the replica's PuppetDB PostgreSQL host
  run_task('pe_xl::pe_install', $puppetdb_database_replica_host,
    tarball => $upload_tarball_path,
  )
  run_task('pe_xl::puppet_runonce', $puppetdb_database_replica_host)

  # Upgrade the compile master group B hosts
  run_task('pe_xl::agent_upgrade', $cm_cluster_replica_hosts,
    server => $primary_master_host,
  )

  # Ensure Puppet running on all infrastructure hosts
  run_task('service', $all_hosts,
    action => 'start',
    name   => 'puppet',
  )

  return('End Plan')
}

