plan pe_xl::install (
  String[1]           $version = '2017.3.5',
  String[1]           $primary_master_host,
  String[1]           $puppetdb_database_host,
  Array[String[1]]    $compile_master_hosts = [ ],
  Array[String[1]]    $dns_alt_names = [ ],
  Optional[String[1]] $load_balancer_host = undef,

  Optional[String[1]] $r10k_remote = undef,
  String[1]           $pe_environment = 'pe',

  Optional[String[1]] $primary_master_replica_host = undef,
  Optional[String[1]] $puppetdb_database_replica_host = undef,
) {

  $all_hosts = [
    $primary_master_host, 
    $puppetdb_database_host,
    $compile_master_hosts,
    $load_balancer_host,
    $primary_master_replica_host,
    $puppetdb_database_replica_host,
  ].pe_xl::flatten_compact()

  # Validate that the name given for each system is both a resolvable name AND
  # the configured hostname.
  run_task('pe_xl::hostname', $all_hosts).each |$task| {
    if $task.target.hostname != $task.result['stdout'] {
      fail_plan("Hostname / DNS name mismatch: ${task}")
    }
  }

  $pe_conf = epp('templates/pe.conf.epp',
    primary_master_host    => $primary_master_host,
    puppetdb_database_host => $puppetdb_database_host,
    dns_alt_names          => $dns_alt_names,
  )

  $puppetdb_database_pe_conf = epp('templates/puppetdb_database-pe.conf.epp',
    primary_master_host    => $primary_master_host,
    puppetdb_database_host => $puppetdb_database_host,
  )

  # Download the PE tarball and send it to the nodes that need it
  $pe_tarball = "puppet-enterprise-${version}-el-7-x86_64.tar.gz"

  run_task('pe_xl::pe_download', 'local://localhost',
    version  => $version,
    filename => $pe_tarball,
  )

  file_upload($pe_tarball, $pe_tarball, [
    $primary_master_host,
    $puppetdb_database_host,
  ])

  # Get the core installation up and running

  pe_xl::file_content_upload($primary_master_pe_conf, 'pe.conf', $primary_master_host)
  run_task('pe_xl::pe_install', $primary_master_host,
    csr_attributes => {
      'pp_auth_role' => 'primary_master',
      'pp_cluster'   => 'puppet-enterprise-A',
    },
  )

  pe_xl::file_content_upload($puppetdb_database_pe_conf, 'pe.conf', $puppetdb_database_host)
  run_task('pe_xl::pe_install', $puppetdb_database_host,
    csr_attributes => {
      'pp_auth_role' => 'puppetdb_database',
      'pp_cluster'   => 'puppet-enterprise-A',
    },
  )

  # Deploy the PE agent to all non-core hosts
  $non_core_hosts = $all_hosts - [$primary_master_host, $puppetdb_database_host]

  run_task('pe_xl::agent_install', $primary_master_replica_host,
    server        => $primary_master_host,
    install_flags => [
      "main:dns_alt_names=${dns_alt_names}",
      'extension_requests:pp_auth_role=primary_master',
      'extension_requests:pp_cluster=puppet-enterprise-B',
    ],
  )

  run_task('pe_xl::agent_install', $puppetdb_database_replica_host,
    server        => $primary_master_host,
    install_flags => [
      'extension_requests:pp_auth_role=puppetdb_database',
      'extension_requests:pp_cluster=puppet-enterprise-B',
    ],
  )

  # TODO: Split the compile masters into two pools, A and B.
  run_task('pe_xl::agent_install', $compile_master_hosts,
    server        => $primary_master_host,
    install_flags => [
      "main:dns_alt_names=${dns_alt_names}",
      'extension_requests:pp_auth_role=compile_master',
      'extension_requests:pp_cluster=puppet-enterprise-A',
    ],
  )

  run_task('pe_xl::agent_install', $load_balancer_host,
    server        => $primary_master_host,
    install_flags => [
      'extension_requests:pp_auth_role=load_balancer',
    ],
  )


}
