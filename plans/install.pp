plan pe_xl::install (
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
  ].flatten

  # Validate that the name given for each system is both a resolvable name AND
  # the configured hostname.
  run_task('pe_xl::hostname', $all_hosts).each |$res| {
    if $res.target.hostname != $res.result['stdout'] {
      fail_plan("Hostname / DNS name mismatch: ${res}")
    }
  }


  $primary_master_pe_conf = epp('templates/primary_master-pe.conf.epp',
    primary_master_host    => $primary_master_host,
    puppetdb_database_host => $puppetdb_database_host,
    dns_alt_names          => $dns_alt_names,
  )

  $primary_master_pe_conf = epp('templates/puppetdb_database-pe.conf.epp',
    primary_master_host    => $primary_master_host,
    puppetdb_database_host => $puppetdb_database_host,
  )

}
