plan pe_xl::configure (
  String[1]           $primary_master_host,
  String[1]           $puppetdb_database_host,
  Array[String[1]]    $compile_master_hosts = [ ],
  Optional[String[1]] $primary_master_replica_host = undef,
  Optional[String[1]] $puppetdb_database_replica_host = undef,

  String[1]           $stagingdir = '/tmp',
) {

  $nm_module_tarball = 'WhatsARanjit-node_manager-0.7.1.tar.gz'
  pe_xl::retrieve_and_upload(
    "https://forge.puppet.com/v3/files/${nm_module_tarball}",
    "${stagingdir}/${nm_module_tarball}",
    "/tmp/${nm_module_tarball}",
    $primary_master_host
  )

  $pexl_module_tarball = 'reidmv-pe_xl-master.tar.gz'
  pe_xl::retrieve_and_upload(
    'https://github.com/reidmv/reidmv-pe_xl/archive/master.tar.gz',
    "${stagingdir}/${pexl_module_tarball}",
    "/tmp/${pexl_module_tarball}",
    $primary_master_host
  )

  run_command("/opt/puppetlabs/bin/puppet module install /tmp/${nm_module_tarball}", $primary_master_host)
  run_command("/opt/puppetlabs/bin/puppet module install /tmp/${pexl_module_tarball}", $primary_master_host)
  run_command('chown -R pe-puppet:pe-puppet /etc/puppetlabs/code', $primary_master_host)

  run_task('pe_xl::puppet_runonce', [
    $primary_master_host,
    $puppetdb_database_host,
    $primary_master_replica_host,
    $puppetdb_database_replica_host,
  ])
}
