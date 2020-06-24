plan peadm::convert (
  # Standard
  Peadm::SingleTargetSpec           $master_host,
  Optional[Peadm::SingleTargetSpec] $master_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String                            $compiler_pool_address = $master_host,
  Array[String]                     $dns_alt_names         = [ ],

  # Options
  Boolean                           $configure_node_groups = true,
) {
  # TODO: read and validate convertable PE version

  # Convert inputs into targets.
  $master_target                    = peadm::get_targets($master_host, 1)
  $master_replica_target            = peadm::get_targets($master_replica_host, 1)
  $puppetdb_database_replica_target = peadm::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)
  $puppetdb_database_target         = peadm::get_targets($puppetdb_database_host, 1)

  $all_targets = peadm::flatten_compact([
    $master_target,
    $master_replica_target,
    $puppetdb_database_replica_target,
    $compiler_targets,
    $puppetdb_database_target,
  ])

  # Ensure input valid for a supported architecture
  $arch = peadm::validate_architecture(
    $master_host,
    $master_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  # Know what version of PE the current targets are
  $pe_version = run_task('peadm::read_file', $master_target,
    path => '/opt/puppetlabs/server/pe_version',
  )[0][content].chomp

  # Get trusted fact information for all compilers. Use peadm::target_name() as
  # the hash key because the apply block below will break trying to parse the
  # $compiler_extensions variable if it has Target-type hash keys.
  $compiler_extensions = run_task('peadm::trusted_facts', $compiler_targets).reduce({}) |$memo,$result| {
    $memo + { $result.target.peadm::target_name() => $result['extensions'] }
  }

  # Clusters A and B are used to divide PuppetDB availability for compilers. If
  # the compilers given already have peadm_availability_group facts designating
  # them A or B, use that. Otherwise, divide them by modulus of 2.
  if $arch['high-availability'] {
    $compiler_a_targets = $compiler_targets.filter |$index,$target| {
      $exts = $compiler_extensions[$target.peadm::target_name()]
      $exts[peadm::oid('peadm_availability_group')] in ['A', 'B'] ? {
        true  => $exts[peadm::oid('peadm_availability_group')] == 'A',
        false => $index % 2 == 0,
      }
    }
    $compiler_b_targets = $compiler_targets.filter |$index,$target| {
      $exts = $compiler_extensions[$target.peadm::target_name()]
      $exts[peadm::oid('peadm_availability_group')] in ['A', 'B'] ? {
        true  => $exts[peadm::oid('peadm_availability_group')] == 'B',
        false => $index % 2 != 0,
      }
    }
  }
  else {
    $compiler_a_targets = $compiler_targets
    $compiler_b_targets = []
  }

  if $pe_version =~ /^2018/ {
    apply($master_target) {
      include peadm::setup::convert_pe2018
    }
  }

  # Modify csr_attributes.yaml and insert the peadm-specific OIDs to identify
  # each server's role and availability group

  run_plan('peadm::util::add_cert_extensions', $master_target,
    master_host => $master_target,
    extensions  => {
      peadm::oid('peadm_role')               => 'puppet/master',
      peadm::oid('peadm_availability_group') => 'A',
    },
  )

  # If the orchestrator is in use, get certs fully straightened up before
  # proceeding
  if $all_targets.any |$target| { $target.protocol == 'pcp' } {
    run_task('peadm::puppet_runonce', $master_target)
    peadm::wait_until_service_ready('orchestrator-service', $master_target)
    wait_until_available($all_targets, wait_time => 120)
  }

  run_plan('peadm::util::add_cert_extensions', $master_replica_target,
    master_host => $master_target,
    extensions  => {
      peadm::oid('peadm_role')               => 'puppet/master',
      peadm::oid('peadm_availability_group') => 'B',
    },
  )

  run_plan('peadm::util::add_cert_extensions', $puppetdb_database_target,
    master_host => $master_target,
    extensions  => {
      peadm::oid('peadm_role')               => 'puppet/puppetdb-database',
      peadm::oid('peadm_availability_group') => 'A',
    },
  )

  run_plan('peadm::util::add_cert_extensions', $puppetdb_database_replica_target,
    master_host => $master_target,
    extensions  => {
      peadm::oid('peadm_role')               => 'puppet/puppetdb-database',
      peadm::oid('peadm_availability_group') => 'B',
    },
  )

  run_plan('peadm::util::add_cert_extensions', $compiler_a_targets,
    master_host => $master_target,
    remove      => ['1.3.6.1.4.1.34380.1.3.13'], # OID form of pp_auth_role
    extensions  => {
      'pp_auth_role'                         => 'pe_compiler',
      peadm::oid('peadm_availability_group') => 'A',
    },
  )

  run_plan('peadm::util::add_cert_extensions', $compiler_b_targets,
    master_host => $master_target,
    remove      => ['1.3.6.1.4.1.34380.1.3.13'], # OID form of pp_auth_role
    extensions  => {
      'pp_auth_role'                         => 'pe_compiler',
      peadm::oid('peadm_availability_group') => 'B',
    },
  )

  # Create the necessary node groups in the console

  if $configure_node_groups {
    apply($master_target) {
      class { 'peadm::setup::node_manager_yaml':
        master_host => $master_target.peadm::target_name(),
      }

      class { 'peadm::setup::node_manager':
        master_host                    => $master_target.peadm::target_name(),
        master_replica_host            => $master_replica_target.peadm::target_name(),
        puppetdb_database_host         => $puppetdb_database_target.peadm::target_name(),
        puppetdb_database_replica_host => $puppetdb_database_replica_target.peadm::target_name(),
        compiler_pool_address          => $compiler_pool_address,
        require                        => Class['peadm::setup::node_manager_yaml'],
      }
    }
  }

  # Run Puppet on all targets to ensure catalogs and exported resources fully
  # up-to-date
  run_task('peadm::puppet_runonce', $all_targets)

  return("Conversion to peadm Puppet Enterprise ${arch['architecture']} succeeded.")
}
