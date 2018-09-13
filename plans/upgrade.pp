plan pe_xl::upgrade (
  String[1]           $primary_master_host,
  String[1]           $puppetdb_database_host,
  String[1]           $primary_master_replica_host,
  String[1]           $puppetdb_database_replica_host,
  Array[String[1]]    $compile_master_hosts = [ ],

#  String[1]           $console_password,
  String[1]           $version = '2018.1.3',

  String[1]           $stagingdir = '/tmp',
) {

  # TODO: Do we need to update the pe.conf(s) with a console password?

  # Download the PE tarball and send it to the nodes that need it
  $pe_tarball_name     = "puppet-enterprise-${version}-el-7-x86_64.tar.gz"
  $local_tarball_path  = "${stagingdir}/${pe_tarball_name}"
  $upload_tarball_path = "/tmp/${pe_tarball_name}"

  pe_xl::retrieve_and_upload(
    "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
    $local_tarball_path,
    $upload_tarball_path,
    $primary_master_host,
  )

  # Upgrade the primary master
  run_task('pe_xl::pe_install', $primary_master_host,
    tarball => $upload_tarball_path,
  )

  return('End Plan')
}

