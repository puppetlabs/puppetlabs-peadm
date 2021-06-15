# @summary Single-entry-point plan for installation and configuration of a new
#   Puppet Enterprise Extra Large cluster.  This plan accepts all parameters
#   used by its sub-plans, and invokes them in order.
#
# @param compiler_pool_address 
#   The service address used by agents to connect to compilers, or the Puppet
#   service. Typically this is a load balancer.
# @param internal_compiler_a_pool_address
#   A load balancer address directing traffic to any of the "A" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
# @param internal_compiler_b_pool_address
#   A load balancer address directing traffic to any of the "B" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
#
plan peadm::install (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Common Configuration
  String                            $console_password,
  String                            $version                          = '2019.8.5',
  Optional[Array[String]]           $dns_alt_names                    = undef,
  Optional[String]                  $compiler_pool_address            = undef,
  Optional[String]                  $internal_compiler_a_pool_address = undef,
  Optional[String]                  $internal_compiler_b_pool_address = undef,
  Optional[Hash]                    $pe_conf_data                     = { },

  # Code Manager
  Optional[String]                  $r10k_remote              = undef,
  Optional[String]                  $r10k_private_key_file    = undef,
  Optional[Peadm::Pem]              $r10k_private_key_content = undef,
  Optional[String]                  $deploy_environment       = undef,

  # License Key
  Optional[String]                  $license_key_file    = undef,
  Optional[String]                  $license_key_content = undef,

  # Other
  Optional[String]                  $stagingdir    = undef,
  Enum[direct,bolthost]             $download_mode = 'bolthost',
) {
  peadm::assert_supported_bolt_version()

  peadm::assert_supported_pe_version($version)

  $install_result = run_plan('peadm::action::install',
    # Standard
    primary_host                   => $primary_host,
    replica_host                   => $replica_host,

    # Large
    compiler_hosts                 => $compiler_hosts,

    # Extra Large
    primary_postgresql_host        => $primary_postgresql_host,
    replica_postgresql_host        => $replica_postgresql_host,

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
    download_mode                  => $download_mode,
  )

  $configure_result = run_plan('peadm::action::configure',
    # Standard
    primary_host                     => $primary_host,
    replica_host                     => $replica_host,

    # Large
    compiler_hosts                   => $compiler_hosts,

    # Extra Large
    primary_postgresql_host          => $primary_postgresql_host,
    replica_postgresql_host          => $replica_postgresql_host,

    # Common Configuration
    compiler_pool_address            => $compiler_pool_address,
    internal_compiler_a_pool_address => $internal_compiler_a_pool_address,
    internal_compiler_b_pool_address => $internal_compiler_b_pool_address,
    deploy_environment               => $deploy_environment,

    # Other
    stagingdir                       => $stagingdir,
  )

  # Return a string banner reporting on what was done
  return([$install_result, $configure_result])
}

