# @summary Upgrade an Extra Large stack from one .z to the next
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
plan peadm::upgrade (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts      = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host         = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Common Configuration
  String           $version,
  Optional[String] $compiler_pool_address            = undef,
  Optional[String] $internal_compiler_a_pool_address = undef,
  Optional[String] $internal_compiler_b_pool_address = undef,

  # Other
  Optional[String]      $token_file    = undef,
  String                $stagingdir    = '/tmp',
  Enum[direct,bolthost] $download_mode = 'bolthost',

  Optional[Enum[
    'upgrade-primary',
    'upgrade-node-groups',
    'upgrade-primary-compilers',
    'upgrade-replica',
    'upgrade-replica-compilers',
    'finalize']] $begin_at_step = undef,
) {
  peadm::assert_supported_bolt_version()

  peadm::assert_supported_pe_version($version)

  # Ensure input valid for a supported architecture
  $arch = peadm::assert_supported_architecture(
    $primary_host,
    $replica_host,
    $primary_postgresql_host,
    $replica_postgresql_host,
    $compiler_hosts,
  )

  # Convert inputs into targets.
  $primary_target                   = peadm::get_targets($primary_host, 1)
  $replica_target           = peadm::get_targets($replica_host, 1)
  $primary_postgresql_target         = peadm::get_targets($primary_postgresql_host, 1)
  $replica_postgresql_target = peadm::get_targets($replica_postgresql_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)

  $all_targets = peadm::flatten_compact([
    $primary_target,
    $primary_postgresql_target,
    $replica_target,
    $replica_postgresql_target,
    $compiler_targets,
  ])

  $pe_installer_targets = peadm::flatten_compact([
    $primary_target,
    $primary_postgresql_target,
    $replica_postgresql_target,
  ])

  out::message('# Gathering information')

  # Gather certificate extension information from all systems
  $cert_extensions = run_task('peadm::cert_data', $all_targets).reduce({}) |$memo,$result| {
    $memo + { $result.target.name => $result['extensions'] }
  }

  $convert_targets = $cert_extensions.filter |$name,$exts| {
    ($name in $compiler_targets.map |$t| { $t.name }) and ($exts['pp_auth_role'] == undef)
  }.keys

  # Determine PE version currently installed on primary
  $current_pe_version = run_task('peadm::read_file', $primary_target,
    path => '/opt/puppetlabs/server/pe_build',
  ).first['content']

  # Ensure needed trusted facts are available
  if $cert_extensions.any |$_,$cert| {
    [peadm::oid('peadm_role'), 'pp_auth_role'].all |$ext| { $cert[$ext] == undef }
  } {
    fail_plan(@(HEREDOC/L))
      Required trusted facts are not present; upgrade cannot be completed. If \
      this infrastructure was provisioned with an old version of peadm, you may \
      need to run the peadm::convert plan\
      | HEREDOC
  }

  # Determine which compilers are associated with which DR group
  $compiler_m1_targets = $compiler_targets.filter |$target| {
    ($cert_extensions[$target.name][peadm::oid('peadm_availability_group')]
      == $cert_extensions[$primary_target[0].name][peadm::oid('peadm_availability_group')])
  }

  $compiler_m2_targets = $compiler_targets.filter |$target| {
    ($cert_extensions[$target.name][peadm::oid('peadm_availability_group')]
      == $cert_extensions[$replica_target[0].name][peadm::oid('peadm_availability_group')])
  }

  $primary_target.peadm::fail_on_transport('pcp')

  $platform = run_task('peadm::precheck', $primary_target).first['platform']
  $tarball_filename = "puppet-enterprise-${version}-${platform}.tar.gz"
  $tarball_source   = "https://s3.amazonaws.com/pe-builds/released/${version}/${tarball_filename}"
  $upload_tarball_path = "/tmp/${tarball_filename}"

  peadm::plan_step('preparation') || {
    # Support for running over the orchestrator transport relies on Bolt being
    # executed from the primary using the local transport. For now, fail the plan
    # if the orchestrator is being used for the primary.
    if $download_mode == 'bolthost' {
      # Download the PE tarball on the nodes that need it
      run_plan('peadm::util::retrieve_and_upload', $pe_installer_targets,
        source      => $tarball_source,
        local_path  => "${stagingdir}/${tarball_filename}",
        upload_path => $upload_tarball_path,
      )
    } else {
      # Download PE tarballs directly to nodes that need it
      run_task('peadm::download', $pe_installer_targets,
        source => $tarball_source,
        path   => $upload_tarball_path,
      )
    }

    # Shut down Puppet on all infra targets. Avoid using the built-in service
    # task for idempotency reasons. When the orchestrator has been upgraded but
    # not all pxp-agents have, the built-in service task does not work over pcp.
    run_command('systemctl stop puppet', $all_targets)

    # Create a variable for configuring PuppetDB access for all the certnames
    # that are known to need it.
    $profile_database_puppetdb_hosts = {
      'puppet_enterprise::profile::database::puppetdb_hosts' => (
        $compiler_targets + $primary_target + $replica_target
      ).map |$t| { $t.peadm::certname() },
    }

    # Ensure the pe.conf files on the PostgreSQL node(s) are correct. This file
    # is only ever consulted during install and upgrade of these nodes, but if
    # it contains the wrong values, upgrade will fail.
    peadm::flatten_compact([
      $primary_postgresql_target,
      $replica_postgresql_target,
    ]).each |$target| {
      $current_pe_conf = run_task('peadm::read_file', $target,
        path => '/etc/puppetlabs/enterprise/conf.d/pe.conf',
      ).first['content']

      $pe_conf = ($current_pe_conf ? {
        undef   => {},
        default => $current_pe_conf.parsehocon(),
      } + {
        'console_admin_password'                => 'not used',
        'puppet_enterprise::puppet_master_host' => $primary_target.peadm::certname(),
        'puppet_enterprise::database_host'      => $target.peadm::certname(),
      } + $profile_database_puppetdb_hosts).to_json_pretty()

      write_file($pe_conf, '/etc/puppetlabs/enterprise/conf.d/pe.conf', $target)
    }
  }

  peadm::plan_step('upgrade-primary') || {
    # Shut down PuppetDB on CMs that use the PM's PDB PG. Use run_command instead
    # of run_task(service, ...) so that upgrading from 2018.1 works over PCP.
    run_command('systemctl stop pe-puppetdb', $compiler_m1_targets)

    run_task('peadm::pe_install', $primary_postgresql_target,
      tarball               => $upload_tarball_path,
      puppet_service_ensure => 'stopped',
    )

    run_task('peadm::pe_install', $primary_target,
      tarball               => $upload_tarball_path,
      puppet_service_ensure => 'stopped',
    )

    # If in use, wait until orchestrator service is healthy to proceed
    if $all_targets.any |$target| { $target.protocol == 'pcp' } {
      peadm::wait_until_service_ready('orchestrator-service', $primary_target)
      wait_until_available($all_targets, wait_time => 120)
    }

    # Installer-driven upgrade will de-configure auth access for compilers.
    # Re-run Puppet immediately to fully re-enable
    run_task('peadm::puppet_runonce', peadm::flatten_compact([
      $primary_target,
      $primary_postgresql_target,
    ]))
  }

  peadm::plan_step('upgrade-node-groups') || {
    # The primary could restart orchestration services again, in which case we
    # would have to wait for nodes to reconnect
    if $all_targets.any |$target| { $target.protocol == 'pcp' } {
      peadm::wait_until_service_ready('orchestrator-service', $primary_target)
      wait_until_available($all_targets, wait_time => 120)
    }

    # If necessary, add missing cert extensions to compilers
    run_plan('peadm::modify_cert_extensions', $convert_targets,
      primary_host => $primary_target,
      add          => {
        'pp_auth_role' => 'pe_compiler',
      },
    )

    # Update classification. This needs to be done now because if we don't, and
    # the PE Compiler node groups are wrong, then the compilers won't be able to
    # successfully classify and update
    apply($primary_target) {
      class { 'peadm::setup::node_manager_yaml':
        primary_host => $primary_target.peadm::certname(),
      }

      class { 'peadm::setup::node_manager':
        primary_host                     => $primary_target.peadm::certname(),
        replica_host                     => $replica_target.peadm::certname(),
        primary_postgresql_host          => $primary_postgresql_target.peadm::certname(),
        replica_postgresql_host          => $replica_postgresql_target.peadm::certname(),
        compiler_pool_address            => $compiler_pool_address,
        internal_compiler_a_pool_address => $internal_compiler_a_pool_address,
        internal_compiler_b_pool_address => $internal_compiler_b_pool_address,
        require                          => Class['peadm::setup::node_manager_yaml'],
      }
    }
  }

  peadm::plan_step('upgrade-primary-compilers') || {
    # Upgrade the compiler group A targets
    run_task('peadm::puppet_infra_upgrade', $primary_target,
      type       => 'compiler',
      targets    => $compiler_m1_targets.map |$t| { $t.peadm::certname() },
      token_file => $token_file,
    )
  }

  peadm::plan_step('upgrade-replica') || {
    # Shut down PuppetDB on CMs that use the replica's PDB PG. Use run_command
    # instead of run_task(service, ...) so that upgrading from 2018.1 works
    # over PCP.
    run_command('systemctl stop pe-puppetdb', $compiler_m2_targets)

    run_task('peadm::pe_install', $replica_postgresql_target,
      tarball               => $upload_tarball_path,
      puppet_service_ensure => 'stopped',
    )

    # Installer-driven upgrade will de-configure auth access for compilers.
    # Re-run Puppet immediately to fully re-enable.
    #
    # Because the steps following involve performing orchestrated actions and
    # `puppet infra upgrade` cannot handle orchestration services restarting,
    # also run Puppet immediately on the primary.
    run_task('peadm::puppet_runonce', peadm::flatten_compact([
      $primary_target,
      $replica_postgresql_target,
    ]))

    # The `puppetdb delete-reports` CLI app has a bug in 2019.8.0 where it
    # doesn't deal well with the PuppetDB database being on a separate node.
    # So, move it aside before running the upgrade.
    $pdbapps = '/opt/puppetlabs/server/apps/puppetdb/cli/apps'
    $workaround_delete_reports = $arch['disaster-recovery'] and $version =~ SemVerRange('>= 2019.8')
    if $workaround_delete_reports {
      run_command(@("COMMAND"/$), $replica_target)
        if [ -e ${pdbapps}/delete-reports -a ! -h ${pdbapps}/delete-reports ]
        then
          mv ${pdbapps}/delete-reports ${pdbapps}/delete-reports.original
          ln -s \$(which true) ${pdbapps}/delete-reports
        fi
        | COMMAND
    }

    # Upgrade the primary replica.
    run_task('peadm::puppet_infra_upgrade', $primary_target,
      type       => 'replica',
      targets    => $replica_target.map |$t| { $t.peadm::certname() },
      token_file => $token_file,
    )

    # Return the delete-reports CLI app to its original state
    if $workaround_delete_reports {
      run_command(@("COMMAND"/$), $replica_target)
        if [ -e ${pdbapps}/delete-reports.original ]
        then
          mv ${pdbapps}/delete-reports.original ${pdbapps}/delete-reports
        fi
        | COMMAND
    }
  }

  peadm::plan_step('upgrade-replica-compilers') || {
    # Upgrade the compiler group B targets
    run_task('peadm::puppet_infra_upgrade', $primary_target,
      type       => 'compiler',
      targets    => $compiler_m2_targets.map |$t| { $t.peadm::certname() },
      token_file => $token_file,
    )
  }

  peadm::plan_step('finalize') || {
    # Ensure Puppet running on all infrastructure targets
    run_task('service', $all_targets,
      action => 'start',
      name   => 'puppet',
    )
  }

  return("Upgrade of Puppet Enterprise ${arch['architecture']} completed.")
}
