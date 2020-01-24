# @summary Upgrade an Extra Large stack from one .z to the next
#
plan peadm::upgrade (
  # Standard
  Peadm::SingleTargetSpec           $master_host,
  Optional[Peadm::SingleTargetSpec] $master_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts      = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Peadm::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String $version,

  # Other
  String[1] $stagingdir = '/tmp',
) {
  # Ensure input valid for a supported architecture
  $arch = peadm::validate_architecture(
    $master_host,
    $master_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  # Convert inputs into targets.
  $master_target                    = peadm::get_targets($master_host, 1)
  $master_replica_target            = peadm::get_targets($master_replica_host, 1)
  $puppetdb_database_target         = peadm::get_targets($puppetdb_database_host, 1)
  $puppetdb_database_replica_target = peadm::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)

  $all_targets = peadm::flatten_compact([
    $master_target,
    $puppetdb_database_target,
    $master_replica_target,
    $puppetdb_database_replica_target,
    $compiler_targets,
  ])

  $pe_installer_targets = peadm::flatten_compact([
    $master_target,
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
  ])

  # Gather trusted facts from all systems
  $trusted_facts = run_task('peadm::trusted_facts', $all_targets).reduce({}) |$memo,$result| {
    $memo + { $result.target => $result['extensions'] }
  }

  # Determine which compilers are associated with which HA group
  $compiler_m1_targets = $compiler_targets.filter |$target| {
    $trusted_facts[$target]['pp_cluster'] == $trusted_facts[$master_target[0]]['pp_cluster']
  }

  $compiler_m2_targets = $compiler_targets.filter |$target| {
    $trusted_facts[$target]['pp_cluster'] == $trusted_facts[$master_replica_target[0]]['pp_cluster']
  }

  ###########################################################################
  # PREPARATION
  ###########################################################################

  # Support for running over the orchestrator transport is still TODO. For now,
  #fail the plan if the orchestrator is being used.
  $all_targets.peadm::fail_on_transport('pcp')

  # Download the PE tarball on the nodes that need it
  $platform = run_task('peadm::precheck', $master_target).first['platform']
  $tarball_filename = "puppet-enterprise-${version}-${platform}.tar.gz"
  $upload_tarball_path = "/tmp/${tarball_filename}"

  run_plan('peadm::util::retrieve_and_upload', $pe_installer_targets,
    source      => "https://s3.amazonaws.com/pe-builds/released/${version}/${tarball_filename}",
    local_path  => "${stagingdir}/${tarball_filename}",
    upload_path => $upload_tarball_path,
  )

  # Shut down Puppet on all infra targets
  run_task('service', $all_targets,
    action => 'stop',
    name   => 'puppet',
  )

  ###########################################################################
  # UPGRADE MASTER SIDE
  ###########################################################################

  # Shut down PuppetDB on CMs that use the PM's PDB PG
  run_task('service', peadm::flatten_compact([
    $master_target,
    $compiler_m1_targets,
  ]),
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  run_task('peadm::pe_install', $puppetdb_database_target,
    tarball => $upload_tarball_path,
  )

  run_task('peadm::pe_install', $master_target,
    tarball => $upload_tarball_path,
  )

  # Installer-driven upgrade will de-configure auth access for compilers.
  # Re-run Puppet immediately to fully re-enable
  run_task('peadm::puppet_runonce', $puppetdb_database_target)


  # Wait until orchestrator service is healthy to proceed
  run_task('peadm::orchestrator_healthcheck', $master_target)

  # Upgrade the compiler group A targets
  run_task('peadm::agent_upgrade', $compiler_m1_targets,
    server => $master_target.peadm::target_name(),
  )

  ###########################################################################
  # UPGRADE REPLICA SIDE
  ###########################################################################

  # Shut down PuppetDB on compilers that use the repica's PDB PG
  run_task('service', peadm::flatten_compact([
    $master_replica_target,
    $compiler_m2_targets,
  ]),
    action => 'stop',
    name   => 'pe-puppetdb',
  )

  run_task('peadm::pe_install', $puppetdb_database_replica_target,
    tarball => $upload_tarball_path,
  )

  # Installer-driven upgrade will de-configure auth access for compilers.
  # Re-run Puppet immediately to fully re-enable
  run_task('peadm::puppet_runonce', $puppetdb_database_replica_target)

  # Run the upgrade.sh script on the master replica target
  run_task('peadm::agent_upgrade', $master_replica_target,
    server => $master_target.peadm::target_name(),
  )

  # Upgrade the compiler group B targets
  run_task('peadm::agent_upgrade', $compiler_m2_targets,
    server => $master_target.peadm::target_name(),
  )

  ###########################################################################
  # FINALIZE UPGRADE
  ###########################################################################

  # Ensure Puppet running on all infrastructure targets
  run_task('service', $all_targets,
    action => 'start',
    name   => 'puppet',
  )

  return('End Plan')
}

