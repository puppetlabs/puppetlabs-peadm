# @summary Perform initial installation of Puppet Enterprise Extra Large
#
# @param r10k_remote
#   The clone URL of the controlrepo to use. This just uses the basic config
#   from the documentaion https://puppet.com/docs/pe/2019.0/code_mgr_config.html
#
# @param r10k_private_key
#   The private key to use for r10k. If this is a local file it will be copied
#   over to the masters at /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa
#   If the file does not exist the value will simply be supplied to the masters
#
# @param pe_conf_data
#   Config data to plane into pe.conf when generated on all hosts, this can be
#   used for tuning data etc.
#
plan pe_xl::unit::install (
  # Standard
  Pe_xl::SingleTargetSpec           $master_host,
  Optional[Pe_xl::SingleTargetSpec] $master_replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts      = undef,

  # Extra Large
  Optional[Pe_xl::SingleTargetSpec] $puppetdb_database_host         = undef,
  Optional[Pe_xl::SingleTargetSpec] $puppetdb_database_replica_host = undef,

  # Common Configuration
  String               $console_password,
  String               $version       = '2019.1.1',
  Array[String]        $dns_alt_names = [ ],
  Hash                 $pe_conf_data  = { },

  # Code Manager
  Optional[String]     $r10k_remote              = undef,
  Optional[String]     $r10k_private_key_file    = undef,
  Optional[Pe_xl::Pem] $r10k_private_key_content = undef,

  # Other
  String               $stagingdir   = '/tmp',
) {
  # Convert inputs into targets.
  $master_target                    = pe_xl::get_targets($master_host, 1)
  $master_replica_target            = pe_xl::get_targets($master_replica_host, 1)
  $puppetdb_database_target         = pe_xl::get_targets($puppetdb_database_host, 1)
  $puppetdb_database_replica_target = pe_xl::get_targets($puppetdb_database_replica_host, 1)
  $compiler_targets                 = pe_xl::get_targets($compiler_hosts)

  # Ensure input valid for a supported architecture
  $arch = pe_xl::validate_architecture(
    $master_host,
    $master_replica_host,
    $puppetdb_database_host,
    $puppetdb_database_replica_host,
    $compiler_hosts,
  )

  $all_targets = pe_xl::flatten_compact([
    $master_target,
    $puppetdb_database_target,
    $master_replica_target,
    $puppetdb_database_replica_target,
    $compiler_targets,
  ])

  $database_targets = pe_xl::flatten_compact([
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
  ])

  $pe_installer_targets = pe_xl::flatten_compact([
    $master_target,
    $puppetdb_database_target,
    $puppetdb_database_replica_target,
  ])

  $agent_installer_targets = pe_xl::flatten_compact([
    $compiler_targets,
    $master_replica_target,
  ])

  # Clusters A and B are used to divide PuppetDB availability for compilers
  if $arch['high-availability'] {
    $compiler_a_targets = $compiler_targets.filter |$index,$target| { $index % 2 == 0 }
    $compiler_b_targets = $compiler_targets.filter |$index,$target| { $index % 2 != 0 }
  }
  else {
    $compiler_a_targets = $compiler_targets
    $compiler_b_targets = []
  }

  $dns_alt_names_csv = $dns_alt_names.reduce |$csv,$x| { "${csv},${x}" }

  # Process user input for r10k private key (content or file) and set
  # appropriate value in $r10k_private_key. The value of this variable should
  # either be undef or else the key content to write.
  $r10k_private_key = [
    $r10k_private_key_file,
    $r10k_private_key_content,
  ].pe_xl::flatten_compact.size ? {
    0 => undef, # no key data supplied
    2 => fail('Must specify either one or neither of r10k_private_key_file and r10k_private_key_content; not both'),
    1 => $r10k_private_key_file ? {
      String => file($r10k_private_key_file), # key file path supplied, read data from file
      undef  => $r10k_private_key_content,    # key content supplied directly, use as-is
    },
  }

  # Validate that the name given for each system is both a resolvable name AND
  # the configured hostname.
  run_task('pe_xl::hostname', $all_targets).each |$result| {
    if $result.target.name != $result['hostname'] {
      fail_plan("Hostname / DNS name mismatch: target ${result.target.name} reports '${result['hostname']}'")
    }
  }

  # Generate all the needed pe.conf files
  $master_pe_conf = pe_xl::generate_pe_conf({
    'console_admin_password'                                          => $console_password,
    'puppet_enterprise::puppet_master_host'                           => $master_target.pe_xl::target_host(),
    'pe_install::puppet_master_dnsaltnames'                           => $dns_alt_names,
    'puppet_enterprise::profile::puppetdb::database_host'             => $puppetdb_database_target.pe_xl::target_host(),
    'puppet_enterprise::profile::master::code_manager_auto_configure' => true,
    'puppet_enterprise::profile::master::r10k_private_key'            => '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa',
    'puppet_enterprise::profile::master::r10k_remote'                 => $r10k_remote,
  } + $pe_conf_data)

  $puppetdb_database_pe_conf = pe_xl::generate_pe_conf({
    'console_admin_password'                => 'not used',
    'puppet_enterprise::puppet_master_host' => $master_target.pe_xl::target_host(),
    'puppet_enterprise::database_host'      => $puppetdb_database_target.pe_xl::target_host(),
  } + $pe_conf_data)

  $puppetdb_database_replica_pe_conf = pe_xl::generate_pe_conf({
    'console_admin_password'                => 'not used',
    'puppet_enterprise::puppet_master_host' => $master_target.pe_xl::target_host(),
    'puppet_enterprise::database_host'      => $puppetdb_database_replica_target.pe_xl::target_host(),
  } + $pe_conf_data)

  # Upload the pe.conf files to the hosts that need them
  pe_xl::file_content_upload($master_pe_conf, '/tmp/pe.conf', $master_target)
  pe_xl::file_content_upload($puppetdb_database_pe_conf, '/tmp/pe.conf', $puppetdb_database_target)
  pe_xl::file_content_upload($puppetdb_database_replica_pe_conf, '/tmp/pe.conf', $puppetdb_database_replica_target)

  # Download the PE tarball and send it to the nodes that need it
  $pe_tarball_name     = "puppet-enterprise-${version}-el-7-x86_64.tar.gz"
  $local_tarball_path  = "${stagingdir}/${pe_tarball_name}"
  $upload_tarball_path = "/tmp/${pe_tarball_name}"

  run_plan('pe_xl::util::retrieve_and_upload', $pe_installer_targets,
    source      => "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
    local_path  => $local_tarball_path,
    upload_path => $upload_tarball_path,
  )

  # Create csr_attributes.yaml files for the nodes that need them
  run_task('pe_xl::mkdir_p_file', $master_target,
    path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    content => @(HEREDOC),
      ---
      extension_requests:
        pp_application: "puppet"
        pp_role: "pe_xl::master"
        pp_cluster: "A"
      | HEREDOC
  )

  run_task('pe_xl::mkdir_p_file', $puppetdb_database_target,
    path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    content => @(HEREDOC),
      ---
      extension_requests:
        pp_application: "puppet"
        pp_role: "pe_xl::puppetdb_database"
        pp_cluster: "A"
      | HEREDOC
  )

  run_task('pe_xl::mkdir_p_file', $puppetdb_database_replica_target,
    path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    content => @(HEREDOC),
      ---
      extension_requests:
        pp_application: "puppet"
        pp_role: "pe_xl::puppetdb_database"
        pp_cluster: "B"
      | HEREDOC
  )

  # Get the master installation up and running. The installer will
  # "fail" because PuppetDB can't start, if puppetdb_database_target
  # is set. That's expected.
  $shortcircuit_puppetdb = !($puppetdb_database_target.empty)
  without_default_logging() || {
    out::message("Starting: task pe_xl::pe_install on ${master_target[0].name}")
    run_task('pe_xl::pe_install', $master_target,
      _catch_errors         => $shortcircuit_puppetdb,
      tarball               => $upload_tarball_path,
      peconf                => '/tmp/pe.conf',
      shortcircuit_puppetdb => $shortcircuit_puppetdb,
    )
    out::message("Finished: task pe_xl::pe_install on ${master_target[0].name}")
  }

  if $r10k_private_key {
    run_task('pe_xl::mkdir_p_file', [$master_target, $master_replica_target],
      path    => '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa',
      owner   => 'pe-puppet',
      group   => 'pe-puppet',
      mode    => '0400',
      content => $r10k_private_key,
    )
  }

  # Configure autosigning for the puppetdb database hosts 'cause they need it
  $autosign_conf = $database_targets.reduce('') |$memo,$target| { "${target.host}\n${memo}" }
  run_task('pe_xl::mkdir_p_file', $master_target,
    path    => '/etc/puppetlabs/puppet/autosign.conf',
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0644',
    content => $autosign_conf,
  )

  # Run the PE installer on the puppetdb database hosts
  run_task('pe_xl::pe_install', $database_targets,
    tarball => $upload_tarball_path,
    peconf  => '/tmp/pe.conf',
  )

  # Now that the main PuppetDB database node is ready, finish priming the
  # master. Explicitly stop puppetdb first to avoid any systemd interference.
  run_command('systemctl stop pe-puppetdb', $master_target)
  run_command('systemctl start pe-puppetdb', $master_target)
  run_task('pe_xl::rbac_token', $master_target,
    password => $console_password,
  )

  # Stub a production environment and commit it to file-sync. At least one
  # commit (content irrelevant) is necessary to be able to configure
  # replication. A production environment must exist when committed to avoid
  # corrupting the PE console. Create the site.pp file specifically to avoid
  # breaking the `puppet infra configure` command.
  run_task('pe_xl::mkdir_p_file', $master_target,
    path    => '/etc/puppetlabs/code-staging/environments/production/manifests/site.pp',
    chown_r => '/etc/puppetlabs/code-staging/environments',
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0644',
    content => "# Empty manifest\n",
  )

  run_task('pe_xl::code_manager', $master_target,
    action => 'file-sync commit',
  )

  # Deploy the PE agent to all remaining hosts
  run_task('pe_xl::agent_install', $master_replica_target,
    server        => $master_target.pe_xl::target_host(),
    install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::master',
      'extension_requests:pp_cluster=B',
    ],
  )

  run_task('pe_xl::agent_install', $compiler_a_targets,
    server        => $master_target.pe_xl::target_host(),
    install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::compiler',
      'extension_requests:pp_cluster=A',
    ],
  )

  run_task('pe_xl::agent_install', $compiler_b_targets,
    server        => $master_target.pe_xl::target_host(),
    install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::compiler',
      'extension_requests:pp_cluster=B',
    ],
  )

  # Ensure certificate requests have been submitted
  run_command(@(HEREDOC), $agent_installer_targets)
    /opt/puppetlabs/bin/puppet ssl submit_request
    | HEREDOC

  # TODO: come up with an intelligent way to validate that the expected CSRs
  # have been submitted and are available for signing, prior to signing them.
  # For now, waiting a short period of time is necessary to avoid a small race.
  ctrl::sleep(15)

  if !empty($agent_installer_targets) {
    run_command(inline_epp(@(HEREDOC/L)), $master_target)
      /opt/puppetlabs/bin/puppetserver ca sign --certname \
        <%= $agent_installer_targets.map |$target| { $target.host }.join(',') -%>
      | HEREDOC
  }

  run_task('pe_xl::puppet_runonce', $master_target)
  run_task('pe_xl::puppet_runonce', $all_targets - $master_target)

  return("Installation of Puppet Enterprise ${arch['architecture']} succeeded.")
}
