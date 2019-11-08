# @summary Single-entry-point plan for installation and configuration of a new
#   Puppet Enterprise Extra Large cluster.  This plan accepts all parameters
#   used by its sub-plans, and invokes them in order.
#
plan pe_xl::provision (
  # Standard
  Pe_xl::SingleTargetSpec           $master_host,
  Optional[Pe_xl::SingleTargetSpec] $master_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Pe_xl::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Pe_xl::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String                            $console_password,
  String                            $version               = '2019.1.1',
  Optional[Array[String]]           $dns_alt_names         = undef,
  Optional[String]                  $compiler_pool_address = undef,
  Optional[Hash]                    $pe_conf_data          = { },

  # Code Manager
  Optional[String]                  $r10k_remote              = undef,
  Optional[String]                  $r10k_private_key_file    = undef,
  Optional[Pe_xl::Pem]              $r10k_private_key_content = undef,
  Optional[String]                  $deploy_environment       = undef,

  # Other
  Optional[String]                  $stagingdir = undef,
) {

  $install_result = run_plan('pe_xl::unit::install',
    # Standard
    master_host                    => $master_host,
    master_replica_host            => $master_replica_host,

    # Large
    compiler_hosts                 => $compiler_hosts,

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

  $configure_result = run_plan('pe_xl::unit::configure',
    # Standard
    master_host                    => $master_host,
    master_replica_host            => $master_replica_host,

    # Large
    compiler_hosts                 => $compiler_hosts,

    # Extra Large
    puppetdb_database_host         => $puppetdb_database_host,
    puppetdb_database_replica_host => $puppetdb_database_replica_host,

    # Common Configuration
    compiler_pool_address          => $compiler_pool_address,
    deploy_environment             => $deploy_environment,

    # Other
    stagingdir                     => $stagingdir,
  )

  # Return a string banner reporting on what was done
  return([$install_result, $configure_result])
}
