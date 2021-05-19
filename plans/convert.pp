plan peadm::convert (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  Optional[Peadm::SingleTargetSpec] $primary_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String                            $compiler_pool_address            = $primary_host,
  Optional[String]                  $internal_compiler_a_pool_address = undef,
  Optional[String]                  $internal_compiler_b_pool_address = undef,
  Array[String]                     $dns_alt_names                    = [ ],

  Optional[Enum[
    'convert-primary',
    'convert-replica',
    'convert-database',
    'convert-database-replica',
    'convert-compilers-a',
    'convert-compilers-b',
    'convert-node-groups',
    'finalize']] $begin_at_step = undef,
) {
  peadm::check_bolt_version()

  # TODO: read and validate convertable PE version

  # Convert inputs into targets.
  $master_target                    = peadm::get_targets($primary_host, 1)
  $master_replica_target            = peadm::get_targets($primary_replica_host, 1)
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
    $primary_host,
    $primary_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  out::message('# Gathering information')

  # Get trusted fact information for all compilers. Use peadm::target_name() as
  # the hash key because the apply block below will break trying to parse the
  # $compiler_extensions variable if it has Target-type hash keys.
  $cert_extensions = run_task('peadm::trusted_facts', $all_targets).reduce({}) |$memo,$result| {
    $memo + { $result.target.peadm::target_name() => $result['extensions'] }
  }

  # Know what version of PE the current targets are
  $pe_version = run_task('peadm::read_file', $master_target,
    path => '/opt/puppetlabs/server/pe_version',
  )[0][content].chomp

  # Figure out if this PE deployment has been configured with peadm or pe_xl
  # before
  $previously_configured_by_peadm = $all_targets.any |$target| {
    $exts = $cert_extensions[$target.peadm::target_name()]
    $exts[peadm::oid('peadm_role')] or String($exts[peadm::oid('pp_role')]) =~ /pe_xl|peadm/
  }

  if (!$previously_configured_by_peadm and ($pe_version =~ SemVerRange('< 2019.7.0'))) {
    fail_plan(@("EOL"/L))
      PE deployment cannot be converted! PE deployment must be a deployment \
      created by pe_xl, by an older version of peadm, or be PE version \
      2019.7.0 or newer. Detected PE version ${pe_version}, and did not detect \
      signs that the deployment was previously created by peadm/pe_xl.
      | EOL
  }

  # Clusters A and B are used to divide PuppetDB availability for compilers. If
  # the compilers given already have peadm_availability_group facts designating
  # them A or B, use that. Otherwise, divide them by modulus of 2.
  if $arch['high-availability'] {
    $compiler_a_targets = $compiler_targets.filter |$index,$target| {
      $exts = $cert_extensions[$target.peadm::target_name()]
      if ($exts[peadm::oid('peadm_availability_group')] in ['A', 'B']) {
        $exts[peadm::oid('peadm_availability_group')] == 'A'
      }
      elsif ($exts[peadm::oid('pp_cluster')] in ['A', 'B']) {
        $exts[peadm::oid('pp_cluster')] == 'A'
      }
      else {
        $index % 2 == 0
      }
    }
    $compiler_b_targets = $compiler_targets.filter |$index,$target| {
      $exts = $cert_extensions[$target.peadm::target_name()]
      if ($exts[peadm::oid('peadm_availability_group')] in ['A', 'B']) {
        $exts[peadm::oid('peadm_availability_group')] == 'B'
      }
      elsif ($exts[peadm::oid('pp_cluster')] in ['A', 'B']) {
        $exts[peadm::oid('pp_cluster')] == 'B'
      }
      else {
        $index % 2 != 0
      }
    }
  }
  else {
    $compiler_a_targets = $compiler_targets
    $compiler_b_targets = []
  }

  # Modify csr_attributes.yaml and insert the peadm-specific OIDs to identify
  # each server's role and availability group

  peadm::plan_step('convert-primary') || {
    # If PE version is older than 2019.7
    if (versioncmp($pe_version, '2019.7.0') < 0) {
      apply($master_target) {
        include peadm::setup::convert_pre20197
      }
    }

    run_plan('peadm::util::add_cert_extensions', $master_target,
      primary_host => $master_target,
      extensions  => {
        peadm::oid('peadm_role')               => 'puppet/master',
        peadm::oid('peadm_availability_group') => 'A',
      },
    )
  }

  peadm::plan_step('convert-replica') || {
    # If the orchestrator is in use, get certs fully straightened up before
    # proceeding
    if $all_targets.any |$target| { $target.protocol == 'pcp' } {
      run_task('peadm::puppet_runonce', $master_target)
      peadm::wait_until_service_ready('orchestrator-service', $master_target)
      wait_until_available($all_targets, wait_time => 120)
    }

    run_plan('peadm::util::add_cert_extensions', $master_replica_target,
      primary_host => $master_target,
      extensions  => {
        peadm::oid('peadm_role')               => 'puppet/master',
        peadm::oid('peadm_availability_group') => 'B',
      },
    )
  }

  peadm::plan_step('convert-database') || {
    run_plan('peadm::util::add_cert_extensions', $puppetdb_database_target,
      primary_host => $master_target,
      extensions  => {
        peadm::oid('peadm_role')               => 'puppet/puppetdb-database',
        peadm::oid('peadm_availability_group') => 'A',
      },
    )
  }

  peadm::plan_step('convert-database-replica') || {
    run_plan('peadm::util::add_cert_extensions', $puppetdb_database_replica_target,
      primary_host => $master_target,
      extensions  => {
        peadm::oid('peadm_role')               => 'puppet/puppetdb-database',
        peadm::oid('peadm_availability_group') => 'B',
      },
    )
  }

  peadm::plan_step('convert-compilers-a') || {
    run_plan('peadm::util::add_cert_extensions', $compiler_a_targets,
      primary_host => $master_target,
      extensions  => {
        peadm::oid('pp_auth_role')             => 'pe_compiler',
        peadm::oid('peadm_availability_group') => 'A',
      },
    )
  }

  peadm::plan_step('convert-compilers-b') || {
    run_plan('peadm::util::add_cert_extensions', $compiler_b_targets,
      primary_host => $master_target,
      extensions  => {
        peadm::oid('pp_auth_role')             => 'pe_compiler',
        peadm::oid('peadm_availability_group') => 'B',
      },
    )
  }

  peadm::plan_step('convert-node-groups') || {
    # Create the necessary node groups in the console, unless the PE version is
    # too old to support it pre-upgrade. In that circumstance, we trust that
    # the existing groups are correct enough to function until the upgrade is
    # performed.
    if (versioncmp($pe_version, '2019.7.0') >= 0) {
      apply($master_target) {
        class { 'peadm::setup::node_manager_yaml':
          primary_host => $master_target.peadm::target_name(),
        }

        class { 'peadm::setup::node_manager':
          primary_host                     => $master_target.peadm::target_name(),
          primary_replica_host             => $master_replica_target.peadm::target_name(),
          puppetdb_database_host           => $puppetdb_database_target.peadm::target_name(),
          puppetdb_database_replica_host   => $puppetdb_database_replica_target.peadm::target_name(),
          compiler_pool_address            => $compiler_pool_address,
          internal_compiler_a_pool_address => $internal_compiler_a_pool_address,
          internal_compiler_b_pool_address => $internal_compiler_b_pool_address,
          require                          => Class['peadm::setup::node_manager_yaml'],
        }
      }
    }
    else {
      out::message(@("EOL"/L))
        NOTICE: Node groups not created/updated as part of convert because PE \
        version is too old to support them. Node groups will be updated when \
        the peadm::upgrade plan is run.
        | EOL
    }
  }

  peadm::plan_step('finalize') || {
    # Run Puppet on all targets to ensure catalogs and exported resources fully
    # up-to-date. Run on master first in case puppet server restarts, 'cause
    # that would cause the runs to fail on all the rest.
    run_task('peadm::puppet_runonce', $master_target)
    run_task('peadm::puppet_runonce', $all_targets - $master_target)
  }

  return("Conversion to peadm Puppet Enterprise ${arch['architecture']} completed.")
}
