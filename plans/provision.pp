# @summary Single-entry-point plan for installation and configuration of a new
#   Puppet Enterprise Extra Large cluster.  This plan accepts all parameters
#   used by its sub-plans, and invokes them in order.
#
plan pe_xl::provision (
  String[1]                  $master_host,
  Optional[String[1]]        $puppetdb_database_host         = undef,
  Optional[String[1]]        $master_replica_host            = undef,
  Optional[String[1]]        $puppetdb_database_replica_host = undef,
  Optional[Array[String[1]]] $compiler_hosts                 = undef,

  String[1]                  $version,
  String[1]                  $console_password,
  Optional[Array[String[1]]] $dns_alt_names         = undef,
  Optional[String[1]]        $compiler_pool_address = undef,
  Optional[Hash]             $pe_conf_data          = undef,

  Optional[String]           $r10k_remote              = undef,
  Optional[String]           $r10k_private_key_file    = undef,
  Optional[Pe_xl::Pem]       $r10k_private_key_content = undef,
  Optional[String[1]]        $deploy_environment       = undef,

  Optional[String[1]]        $stagingdir          = undef,
  Optional[Boolean]          $executing_on_master = undef,
) {

  run_plan('pe_xl::install',
    # Large
    master_host                    => $master_host,
    compiler_hosts                 => $compiler_hosts,
    master_replica_host            => $master_replica_host,

    # Extra Large
    puppetdb_database_host         => $puppetdb_database_host,
    puppetdb_database_replica_host => $puppetdb_database_replica_host,

    # Common Configuration
    version                        => $version,
    console_password               => $console_password,
    dns_alt_names                  => $dns_alt_names,
    pe_conf_data                   => $pe_conf_data,

    # Code Manager
    r10k_remote                    => $r10k_remote,
    r10k_private_key_file          => $r10k_private_key_file,
    r10k_private_key_content       => $r10k_private_key_content,

    # Other
    stagingdir                     => $stagingdir,
  )

  run_plan('pe_xl::configure',
    # Large
    master_host                    => $master_host,
    compiler_hosts                 => $compiler_hosts,
    master_replica_host            => $master_replica_host,

    # Extra Large
    puppetdb_database_host         => $puppetdb_database_host,
    puppetdb_database_replica_host => $puppetdb_database_replica_host,

    # Common Configuration
    compiler_pool_address          => $compiler_pool_address,
    deploy_environment             => $deploy_environment,

    # Other
    stagingdir                     => $stagingdir,
    executing_on_master            => $executing_on_master,
  )

  # Return a string banner reporting on what was done
  return('Provisioned Puppet Enterprise Extra Large cluster')
}
