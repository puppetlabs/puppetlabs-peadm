# @summary Single-entry-point plan for installation and configuration of a new
#   Puppet Enterprise Extra Large cluster.  This plan accepts all parameters
#   used by its sub-plans, and invokes them in order.
#
plan peadm::provision (
  # Standard
  Peadm::SingleTargetSpec           $master_host,
  Optional[Peadm::SingleTargetSpec] $master_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String                            $console_password,
  String                            $version               = '2019.1.1',
  Optional[Array[String]]           $dns_alt_names         = undef,
  Optional[String]                  $compiler_pool_address = undef,
  Optional[Hash]                    $pe_conf_data          = { },

  # Code Manager
  Optional[String]                  $r10k_remote              = undef,
  Optional[String]                  $r10k_private_key_file    = undef,
  Optional[Peadm::Pem]              $r10k_private_key_content = undef,
  Optional[String]                  $deploy_environment       = undef,

  # License Key
  Optional[String]                  $license_key_file    = undef,
  Optional[String]                  $license_key_content = undef,

  # Other
  Optional[String]                  $stagingdir = undef,
  Optional[String]                  $pp_application_compiler = 'puppet/compiler',
  Optional[String]                  $pp_application_master = 'puppet/master',
  Optional[String]                  $pp_application_puppetdb = 'puppet/puppetdb-database',
  Optional[String]                  $pp_cluster_a = 'A',
  Optional[String]                  $pp_cluster_b = 'B',
) {

  $install_result = run_plan('peadm::action::install',
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

    # License Key
    license_key_file               => $license_key_file,
    license_key_content            => $license_key_content,

    # Other
    stagingdir                     => $stagingdir,
    pp_application_compiler        => $pp_application_compiler,
    pp_application_master          => $pp_application_master,
    pp_application_puppetdb        => $pp_application_puppetdb,
    pp_cluster_a                   => $pp_cluster_a,
    pp_cluster_b                   => $pp_cluster_b,
  )

  $configure_result = run_plan('peadm::action::configure',
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
    pp_application_compiler        => $pp_application_compiler,
    pp_application_master          => $pp_application_master,
    pp_application_puppetdb        => $pp_application_puppetdb,
    pp_cluster_a                   => $pp_cluster_a,
    pp_cluster_b                   => $pp_cluster_b,
  )

  # Return a string banner reporting on what was done
  return([$install_result, $configure_result])
}

