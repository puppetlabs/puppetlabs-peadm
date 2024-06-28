plan peadm::util::init_db_server(
  String[1] $db_host,
  Boolean $install_pe = false,
  String[1] $pe_version = '2023.5.0',
  String[1] $pe_platform = 'el-8-x86_64',
) {
  $t = get_targets('*')
  wait_until_available($t)

  $db_target = get_target($db_host)
  parallelize($t + $db_target) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $primary_target = $t.filter |$n| { $n.vars['role'] == 'primary' }[0]
  $compiler_targets = $t.filter |$n| { $n.vars['role'] == 'compiler' }

  out::message("db_target: ${db_target}")
  out::message("db_target certname: ${db_target.peadm::certname()}")
  out::message("primary_target: ${primary_target}")
  out::message("compiler_targets: ${compiler_targets}")
  run_command("/opt/puppetlabs/bin/puppetserver ca clean --certname ${db_target.peadm::certname()}", $primary_target)

# lint:ignore:strict_indent
  run_task('peadm::mkdir_p_file', $db_target,
    path    => '/etc/puppetlabs/puppet/puppet.conf',
    content => @("HEREDOC"),
      [main]
      certname = ${db_target.peadm::certname()}
      | HEREDOC
# lint:endignore
  )

  run_plan('peadm::util::insert_csr_extension_requests', $db_target,
    extension_requests => {
      peadm::oid('peadm_role')               => 'puppet/puppetdb-database',
      peadm::oid('peadm_availability_group') => 'A',
  })

  $uploaddir = '/tmp'
  $pe_tarball_name   = "puppet-enterprise-${pe_version}-${pe_platform}.tar.gz"
  $pe_tarball_source = "https://s3.amazonaws.com/pe-builds/released/${pe_version}/${pe_tarball_name}"
  $upload_tarball_path = "${uploaddir}/${pe_tarball_name}"

  run_task('peadm::download', $db_target,
    source => $pe_tarball_source,
    path   => $upload_tarball_path,
  )

  run_command('systemctl stop pe-puppetdb', $compiler_targets, { _catch_errors => true })
  # run_task('service', $primary_target, { action => 'restart', name => 'pe-puppetdb',  _catch_errors => true })

  if $install_pe {
    $pe_conf_data = {}

    $puppetdb_database_temp_config = {
      'puppet_enterprise::profile::database::puppetdb_hosts' => (
        $compiler_targets + $primary_target
      ).map |$t| { $t.peadm::certname() },
    }

    $primary_postgresql_pe_conf = peadm::generate_pe_conf({
        'console_admin_password'                => 'not used',
        'puppet_enterprise::puppet_master_host' => $primary_target.peadm::certname(),
        'puppet_enterprise::database_host'      => $db_target.peadm::certname(),
    } + $puppetdb_database_temp_config + $pe_conf_data)

    # Upload the pe.conf files to the hosts that need them, and ensure correctly
    # configured certnames. Right now for these hosts we need to do that by
    # staging a puppet.conf file.

    peadm::file_content_upload($primary_postgresql_pe_conf, '/tmp/pe.conf', $db_target)

    # Run the PE installer on the puppetdb database hosts
    run_task('peadm::pe_install', $db_target,
      tarball               => $upload_tarball_path,
      peconf                => '/tmp/pe.conf',
      puppet_service_ensure => 'stopped',
    )
  }

  run_plan('peadm::subplans::component_install', $db_target, {
      primary_host => $primary_target,
      avail_group_letter => 'A',
      role => 'puppet/puppetdb-database',
  })
  run_task('peadm::puppet_runonce', $compiler_targets)
  run_command('systemctl start pe-puppetdb', $compiler_targets, { _catch_errors => true })
  run_task('service', $compiler_targets, { action => 'restart', name => 'pe-puppetserver',  _catch_errors => true })
}
