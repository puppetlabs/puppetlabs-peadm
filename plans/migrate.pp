# @summary Migrate a PE installation to new host(s)
#
# @param old_primary_host
#   The existing PE primary server that will be migrated from
# @param new_primary_host
#   The new server that will become the PE primary server
# @param upgrade_version
#   Optional version to upgrade to after migration is complete
# @param replica_host
#   Optional new replica server to be added to the cluster
# @param primary_postgresql_host
#   Optional new primary PostgreSQL server to be added to the cluster
# @param replica_postgresql_host
#   Optional new replica PostgreSQL server to be added to the cluster
# @param license_key_file
#   Optional path to a local PE license file (on the Bolt controller) to
#   install on the new primary. The plan fails before anything is changed if
#   the file does not exist or cannot be read, if it is blank, or if both
#   license_key_file and license_key_content are given. If neither parameter
#   is given, the plan copies the old primary's license, read from
#   /etc/puppetlabs/license.key, or from /etc/puppetlabs/suite-license.lic if
#   license.key is missing, unreadable, blank, or its read task fails. (The old
#   primary's license files are not read when a license is supplied.) When a
#   license is found or supplied, it is installed on the new primary as
#   /etc/puppetlabs/license.key. If none is found or readable, migration
#   continues and the new primary is installed without a license key. The plan
#   prints a message beginning 'Warning:' in that case (and another when the
#   migration finishes), which cannot tell a missing file from an unreadable or
#   blank one. If a read task itself fails, the file path and the task's error
#   message are printed too, even when the other file then supplies a license.
# @param license_key_content
#   Same as license_key_file, but takes the license text instead of a file
#   path. Cannot be combined with license_key_file, and must not be blank.
# @param download_mode
#   How the PE installer reaches the new hosts, for both the install and the
#   optional upgrade. 'direct' (default) has each new host download it
#   itself; 'bolthost' downloads it to the Bolt host and uploads it to the
#   new hosts, so they need no internet access.
# @param pe_installer_source
#   Optional URL of the PE installer for the old cluster's PE version, which
#   is the version the new primary is first installed at. Defaults to the
#   standard public source.
# @param upgrade_pe_installer_source
#   Optional URL of the PE installer for upgrade_version. Only used when
#   upgrade_version is set. Defaults to the standard public source.
plan peadm::migrate (
  Peadm::SingleTargetSpec $old_primary_host,
  Peadm::SingleTargetSpec $new_primary_host,
  Optional[String] $upgrade_version = undef,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,
  Optional[String] $license_key_file = undef,
  Optional[String] $license_key_content = undef,
  Peadm::Download_mode $download_mode = 'direct',
  Optional[Stdlib::HTTPSUrl] $pe_installer_source = undef,
  Optional[Stdlib::HTTPSUrl] $upgrade_pe_installer_source = undef,
) {
  # Log parameters for debugging. Do not add license_key_file/license_key_content
  # here: this prints values unmasked.
  peadm::log_plan_parameters({
    'old_primary_host' => $old_primary_host,
    'new_primary_host' => $new_primary_host,
    'replica_host' => $replica_host,
    'primary_postgresql_host' => $primary_postgresql_host,
    'replica_postgresql_host' => $replica_postgresql_host,
    'upgrade_version' => $upgrade_version,
    'download_mode' => $download_mode,
    # Log only the tarball name, as peadm::upgrade does: the URL may carry
    # credentials or a signed token. This keeps it out of the console output;
    # Bolt's debug log still records the parameters of the tasks it runs.
    'pe_installer_source' => $pe_installer_source.then |$url| { $url.regsubst(/[?#].*\z/, '').split('/')[-1] },
    'upgrade_pe_installer_source' => $upgrade_pe_installer_source.then |$url| {
      $url.regsubst(/[?#].*\z/, '').split('/')[-1]
    },
  })

  # pre-migration checks
  peadm::assert_supported_bolt_version()
  # Resolve any operator-supplied license now, so that passing both
  # license_key_file and license_key_content fails before any host is touched.
  $supplied_license = peadm::file_or_content('license_key', $license_key_file, $license_key_content)
  if ($license_key_file or $license_key_content) and $supplied_license !~ Pattern[/\S/] {
    # file_or_content has already rejected both being given, so only one is set
    if $license_key_file {
      $blank_param = 'license_key_file'
    } else {
      $blank_param = 'license_key_content'
    }
    fail_plan("${blank_param} was given but is empty or blank")
  }
  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    $permit_unsafe_versions = false
    peadm::assert_supported_pe_version($upgrade_version, $permit_unsafe_versions)
  }

  $new_hosts = peadm::flatten_compact([
      $new_primary_host,
      $replica_host ? { undef => [], default => [$replica_host] },
      $primary_postgresql_host ? { undef => [], default => [$primary_postgresql_host] },
      $replica_postgresql_host ? { undef => [], default => [$replica_postgresql_host] },
  ].flatten)
  $all_hosts = peadm::flatten_compact([
      $old_primary_host,
      $new_hosts,
  ].flatten)
  run_command('hostname', $all_hosts)  # verify can connect to targets

  # verify the cluster we are migrating from is operational and is a supported architecture
  $cluster = run_task('peadm::get_peadm_config', $old_primary_host).first.value
  $error = getvar('cluster.error')
  if $error {
    fail_plan($error)
  }
  $arch = peadm::assert_supported_architecture(
    getvar('cluster.params.primary_host'),
    getvar('cluster.params.replica_host'),
    getvar('cluster.params.primary_postgresql_host'),
    getvar('cluster.params.replica_postgresql_host'),
    getvar('cluster.params.compiler_hosts'),
  )

  $old_primary_platform = run_task('peadm::precheck', $old_primary_host).first['platform']
  $new_primary_platform = run_task('peadm::precheck', $new_primary_host).first['platform']
  out::message("Old primary platform: ${old_primary_platform}")
  out::message("New primary platform: ${new_primary_platform}")

  # Check the installers before the backup, rather than an hour into the
  # migration. Only the first is needed unless upgrade_version is set.
  if $upgrade_pe_installer_source and empty($upgrade_version) {
    out::message('Ignoring upgrade_pe_installer_source: upgrade_version is not set, so there is no upgrade')
  }
  $installers = {
    'pe_installer_source'         => [$pe_installer_source, getvar('cluster.pe_version'), [$new_primary_host]],
    'upgrade_pe_installer_source' => [$upgrade_pe_installer_source, $upgrade_version, $new_hosts],
  }.filter |$param, $installer| { !empty($installer[1]) }

  $installers.each |$param, $installer| {
    [$source, $version, $download_targets] = $installer
    $tarball_name = "puppet-enterprise-${version}-${new_primary_platform}.tar.gz"

    # peadm::install and peadm::upgrade use the URL's file name as the
    # installer's name, and peadm::upgrade takes the version to upgrade to
    # from it, so a mismatch would install the wrong PE or fail mid-way.
    if $source {
      if $source =~ /[?#]/ {
        # lint:ignore:strict_indent
        fail_plan(@("MSG"/L))
          ${param} can't have a query string or fragment (the part after '?' or \
          '#'): PEADM uses the end of the URL as the installer's file name.
          |-MSG
        # lint:endignore
      }
      $source_name = $source.split('/')[-1]
      unless $source_name == $tarball_name {
        # lint:ignore:strict_indent
        fail_plan(@("MSG"/L))
          ${param} must point to ${tarball_name} (PE ${version} for the new \
          primary's platform), but its file name is ${source_name}.
          |-MSG
        # lint:endignore
      }
    }

    run_plan('peadm::util::check_installer_source', $download_targets,
      source        => $source.lest || { "https://s3.amazonaws.com/pe-builds/released/${version}/${tarball_name}" },
      tarball_name  => $tarball_name,
      download_mode => $download_mode,
    )
  }

  # Code Manager settings (PE-45912). The migration replaces the old PE Master
  # node group with the new install's, so install the new primary with the old
  # r10k settings, as peadm::install would with the same parameters. PE Master's
  # puppet_enterprise::profile::master class wins; settings it does not have
  # come from the old primary's pe.conf, where peadm::install also writes
  # r10k_known_hosts. Read before the backup so a failure stops the migration
  # early. Values are never printed: an r10k remote or proxy URL can hold a
  # credential.
  $old_primary_target = get_targets($old_primary_host)[0]
  $old_primary_pe_conf = peadm::get_pe_conf($old_primary_target)
  $old_code_manager = run_task('peadm::get_code_manager_config', $old_primary_target).first['params']
  $old_r10k = [
    'r10k_remote', 'r10k_private_key', 'r10k_known_hosts', 'r10k_git_provider', 'r10k_proxy', 'r10k_postrun',
  ].reduce({}) |$memo, $setting| {
    $value = $old_code_manager[$setting] ? {
      undef   => $old_primary_pe_conf["puppet_enterprise::profile::master::${setting}"],
      default => $old_code_manager[$setting],
    }
    ($value =~ NotUndef and !empty($value)) ? {
      true    => $memo + { $setting => $value },
      default => $memo,
    }
  }
  $code_manager_pe_conf = $old_r10k.reduce({}) |$memo, $entry| {
    $entry[0] in ['r10k_remote', 'r10k_private_key', 'r10k_known_hosts', 'r10k_git_provider'] ? {
      true    => $memo + { "puppet_enterprise::profile::master::${entry[0]}" => $entry[1] },
      default => $memo,
    }
  }
  # PE copies only some r10k settings from pe.conf into the PE Master group at
  # install, so these would be dropped at the new primary's next Puppet run.
  ['r10k_proxy', 'r10k_postrun'].each |$setting| {
    if $setting in $old_r10k {
      out::message(@("MSG"/L))
        Warning: puppet_enterprise::profile::master::${setting} is set on the old primary but is not carried across. \
        Set it on the new PE Master node group after the migration.
        |- MSG
    }
  }

  $backup_file = run_plan('peadm::backup', $old_primary_host, {
      backup_type => 'migration',
  })

  $download_results = download_file($backup_file['path'], 'backup', $old_primary_host)
  $download_path = $download_results[0]['path']

  $backup_filename = basename($backup_file['path'])
  $remote_backup_path = "/tmp/${backup_filename}"

  upload_file($download_path, $remote_backup_path, $new_primary_host)

  $old_primary_password = $old_primary_pe_conf['console_admin_password']
  $old_pe_conf = run_task('peadm::get_peadm_config', $old_primary_target).first.value

  # An operator-supplied license (never blank, checked above) wins; otherwise
  # carry the old primary's license across. Reads use _catch_errors because an
  # unreadable license must not abort the migration. If the read task itself
  # fails (e.g. no python on the old primary) the file path and Bolt's error
  # message are printed. A missing or unreadable file is not a task failure:
  # peadm::read_file returns null content, so it is indistinguishable from no
  # license and is covered by the 'none found or readable' message. So is a
  # readable file that python cannot decode, where the task prints invalid JSON
  # and still exits 0. A blank file counts as no license.
  #
  # The license travels as a plain String, as it does through peadm::install,
  # so Bolt can show it: on the console with -v or --log-level debug, and in
  # bolt-debug.log. Never interpolate it into a message.
  #
  # The 'Could not read' messages below print error.message, which Bolt builds
  # and which, for a failed task, can include the task's own output. The only
  # way peadm::read_file exits non-zero is when it finds no python, and then it
  # prints fixed text, never file contents. Keep it that way.
  $license_key_path = '/etc/puppetlabs/license.key'
  $suite_license_path = '/etc/puppetlabs/suite-license.lic'
  if $supplied_license =~ Pattern[/\S/] {
    $install_license_content = $supplied_license
    $license_source = 'operator-supplied'
  } else {
    $primary_result = run_task('peadm::read_file', $old_primary_target,
      path => $license_key_path,
      _catch_errors => true
    ).first
    unless $primary_result.ok {
      out::message("Could not read ${license_key_path} on the old primary: ${primary_result.error.message}")
    }
    $primary_license = $primary_result['content']
    if $primary_license =~ Pattern[/\S/] {
      $install_license_content = $primary_license
      $license_source = "${license_key_path} on the old primary"
    } else {
      $suite_result = run_task('peadm::read_file', $old_primary_target,
        path => $suite_license_path,
        _catch_errors => true
      ).first
      unless $suite_result.ok {
        out::message("Could not read ${suite_license_path} on the old primary: ${suite_result.error.message}")
      }
      $suite_license = $suite_result['content']
      if $suite_license =~ Pattern[/\S/] {
        $install_license_content = $suite_license
        $license_source = "${suite_license_path} on the old primary"
      } else {
        $install_license_content = undef
        $license_source = 'none found or readable, the new primary will be installed without a license key'
      }
    }
  }
  # $license_source is a fixed string, never the license itself. Keep it that way.
  if $install_license_content {
    out::message("PE license for the new primary: ${license_source}")
  } else {
    out::message("Warning: PE license for the new primary: ${license_source}")
  }

  # Copy the Code Manager deploy key to the same path on the new primary before
  # the install, which configures Code Manager to use it. It goes through the
  # Bolt project's downloads directory, like the backup above, and the local
  # copy is deleted once uploaded.
  $deploy_key = $code_manager_pe_conf['puppet_enterprise::profile::master::r10k_private_key']
  if $deploy_key {
    $key_download = download_file($deploy_key, 'code-manager-key', $old_primary_target, '_catch_errors' => true).first
    if $key_download.ok {
      run_command("mkdir -p -m 0700 ${shellquote(dirname($deploy_key))}", $new_primary_host)
      upload_file($key_download['path'], $deploy_key, $new_primary_host)
      run_command("chmod 0600 ${shellquote($deploy_key)}", $new_primary_host)
      file::delete($key_download['path'])
    } else {
      out::message(@("MSG"/L))
        Warning: could not copy the Code Manager deploy key ${deploy_key} from the old primary: ${key_download.error.message}. \
        Copy it to ${deploy_key} on the new primary before deploying code.
        |- MSG
    }
  }

  run_plan('peadm::install', {
      primary_host                => $new_primary_host,
      console_password            => $old_primary_password,
      code_manager_auto_configure => true,
      download_mode               => $download_mode,
      pe_installer_source         => $pe_installer_source,
      version                     => $old_pe_conf['pe_version'],
      license_key_content         => $install_license_content,
      pe_conf_data                => $code_manager_pe_conf,
  })

  run_plan('peadm::restore', {
      targets          => $new_primary_host,
      restore_type     => 'migration',
      input_file       => $remote_backup_path,
      console_password => $old_primary_password,
  })

  $node_types = {
    'primary_host'             => $old_pe_conf['params']['primary_host'],
    'replica_host'             => $old_pe_conf['params']['replica_host'],
    'primary_postgresql_host'  => $old_pe_conf['params']['primary_postgresql_host'],
    'replica_postgresql_host'  => $old_pe_conf['params']['replica_postgresql_host'],
    'compilers'                => $old_pe_conf['params']['compilers'],
    'legacy_compilers'         => $old_pe_conf['params']['legacy_compilers'],
  }

  $nodes_to_purge = $node_types.reduce([]) |$memo, $entry| {
    $value = $entry[1]

    if empty($value) {
      $memo
    }
    elsif $value =~ Array {
      $memo + $value.filter |$node| { !empty($node) }
    }
    else {
      $memo + [$value]
    }
  }

  out::message("Nodes to purge: ${nodes_to_purge}")

  if !empty($nodes_to_purge) {
    out::message('Purging nodes from old configuration individually')
    $nodes_to_purge.each |$node| {
      out::message("Purging node: ${node}")
      run_command("/opt/puppetlabs/bin/puppet node purge ${node}", $new_primary_host)
    }
  } else {
    out::message('No nodes to purge from old configuration')
  }

  # provision a postgresql host if one is provided
  if $primary_postgresql_host {
    run_plan('peadm::add_database', targets => $primary_postgresql_host,
      primary_host => $new_primary_host,
      is_migration => true,
    )
    # provision a replica postgresql host if one is provided
    if $replica_postgresql_host {
      run_plan('peadm::add_database', targets => $replica_postgresql_host,
        primary_host => $new_primary_host,
        is_migration => true,
      )
    }
  }

  # provision a replica if one is provided
  if $replica_host {
    run_plan('peadm::add_replica', {
        primary_host => $new_primary_host,
        replica_host => $replica_host,
        replica_postgresql_host => $replica_postgresql_host,
    })
  }

  # ensure puppet agent enabled on the hosts we migrated to
  run_command('puppet agent --enable', $new_hosts)

  if $upgrade_version and $upgrade_version != '' and !empty($upgrade_version) {
    run_plan('peadm::upgrade', {
        primary_host                => $new_primary_host,
        version                     => $upgrade_version,
        download_mode               => $download_mode,
        pe_installer_source         => $upgrade_pe_installer_source,
        replica_host                => $replica_host,
        primary_postgresql_host     => $primary_postgresql_host,
        replica_postgresql_host     => $replica_postgresql_host,
    })
  }

  # Say it again now the migration has finished, so it is not lost among the
  # progress output of a long run.
  unless $install_license_content {
    out::message('Warning: migration finished but no license key was installed on the new primary')
  }
}
