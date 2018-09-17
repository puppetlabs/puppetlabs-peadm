# This plan exists as a single entry point which accepts all possible
# parameters and can call sub-plans using them. This is useful so that a single
# params.json file can be used which contains all possible parameters for
# different actions, rather than needing multiple params.json files with
# different combinations of the possible inputs.
plan pe_xl (
  Boolean $install   = false,
  Boolean $configure = false,
  Boolean $upgrade   = false,

  Optional[String[1]]        $primary_master_host = undef,
  Optional[String[1]]        $puppetdb_database_host = undef,
  Optional[String[1]]        $primary_master_replica_host = undef,
  Optional[String[1]]        $puppetdb_database_replica_host = undef,
  Optional[Array[String[1]]] $compile_master_hosts = undef,

  Optional[String[1]]        $console_password = undef,
  Optional[String[1]]        $version = undef,
  Optional[Hash]             $r10k_sources = undef,
  Optional[Array[String[1]]] $dns_alt_names = undef,

  Optional[String[1]]        $compile_master_pool_address = undef,
  Optional[String[1]]        $deploy_environment = undef,

  Optional[String[1]]        $stagingdir = undef,
) {

  if $install {
    run_plan('pe_xl::install',
      primary_master_host            => $primary_master_host,
      puppetdb_database_host         => $puppetdb_database_host,
      primary_master_replica_host    => $primary_master_replica_host,
      puppetdb_database_replica_host => $puppetdb_database_replica_host,
      compile_master_hosts           => $compile_master_hosts,

      console_password               => $console_password,
      version                        => $version,
      r10k_sources                   => $r10k_sources,
      dns_alt_names                  => $dns_alt_names,

      stagingdir                     => $stagingdir,
    )
  }

  if $configure {
    run_plan('pe_xl::configure',
      primary_master_host            => $primary_master_host,
      puppetdb_database_host         => $puppetdb_database_host,
      primary_master_replica_host    => $primary_master_replica_host,
      puppetdb_database_replica_host => $puppetdb_database_replica_host,
      compile_master_hosts           => $compile_master_hosts,

      compile_master_pool_address    => $compile_master_pool_address,
      deploy_environment             => $deploy_environment,

      stagingdir                     => $stagingdir,
    )
  }

  if $upgrade {
    run_plan('pe_xl::upgrade',
      primary_master_host            => $primary_master_host,
      puppetdb_database_host         => $puppetdb_database_host,
      primary_master_replica_host    => $primary_master_replica_host,
      puppetdb_database_replica_host => $puppetdb_database_replica_host,

      version                        => $version,

      stagingdir                     => $stagingdir,
    )
  }

  # Return a string banner reporting on what was done
  $actions = {
    'install'   => $install,
    'configure' => $configure,
    'upgrade'   => $upgrade,
  }.filter |$keypair| {
    $keypair[1] == true
  }.map |$keypair| {
    $keypair[0]
  }.reduce |$actionlist,$action| {
    "${actionlist}, ${action}"
  }

  return("Performed action(s): $actions")
}
