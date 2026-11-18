# @summary Migrate a PE installation to new host(s)
#
# Migrates a PE installation to new host(s). The old primary's Code Manager
# r10k settings (remote, deploy key, known hosts, git provider) are carried
# across to the new primary; see documentation/migration/migrating.md.
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
# @param keep_backup
#   The migration backup holds PE secrets. It is downloaded to the Bolt
#   project's downloads/backup directory and uploaded to /tmp on the new
#   primary, where it is also unpacked. When the migration succeeds, those
#   copies are deleted unless this is true. The old primary's copy is always
#   kept, and the plan says where it is. If the migration fails, nothing is
#   deleted.
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
  Boolean $keep_backup = false,
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
    'keep_backup' => $keep_backup,
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

  # Code Manager settings (PE-45912). The new primary keeps the PE Master node
  # group from its own install, so install it with the old primary's r10k
  # settings and copy the deploy key across. This is done before the backup,
  # so if it stops the plan, nothing has been backed up or installed. Messages
  # never print the remote URL, known hosts or git provider (an r10k remote URL
  # can hold a credential); only a failed key copy names the key's path.
  $old_primary_target = get_targets($old_primary_host)[0]
  $old_primary_pe_conf = peadm::get_pe_conf($old_primary_target)
  $code_manager_types = {
    'r10k_remote'       => String[1],
    # A file under /, with no '..' segment: the plan downloads, uploads and
    # chmods this path as root.
    'r10k_private_key'  => Pattern[/\A(?!.*\/\.\.(?:\/|\z))\/[^\0\n]*[^\/\0\n]\z/],
    'r10k_known_hosts'  => Array[Hash],
    'r10k_git_provider' => Enum['rugged', 'shellgit'],
  }
  $code_manager_expected = {
    'r10k_remote'       => 'a non-empty string',
    'r10k_private_key'  => "an absolute file path with no '..'",
    'r10k_known_hosts'  => 'an array of hashes',
    'r10k_git_provider' => "'rugged' or 'shellgit'",
  }
  $code_manager_read = run_task('peadm::get_code_manager_config', $old_primary_target, '_catch_errors' => true).first
  $code_manager_read_error = if !$code_manager_read.ok {
    $code_manager_read.error.message
  # Bolt wraps _sensitive in Sensitive when it parses real task output; unwrap
  # also accepts a plain value.
  } elsif !($code_manager_read['_sensitive'].unwrap =~ Struct[{ 'settings' => Hash[Enum[$code_manager_types.keys], Data] }]
    and $code_manager_read['not_carried'] =~ Array[String[1]]) {
    'peadm::get_code_manager_config returned output in an unexpected form'
  }
  if $code_manager_read_error {
    $task_error_kind = $code_manager_read.ok ? { true => undef, default => $code_manager_read.error.kind }
    fail_plan(@("MSG"/L), 'peadm/code-manager-settings-unreadable', { 'task_error_kind' => $task_error_kind })
      Could not read the Code Manager settings of the PE Master node group on ${old_primary_host}. \
      Nothing has been changed: fix the cause, then run peadm::migrate again. \
      Error: ${code_manager_read_error}
      |- MSG
  }
  # PE's installer copies r10k_remote, r10k_private_key and r10k_git_provider
  # from pe.conf into the PE Master group, but not r10k_known_hosts
  # (pe_install::install::classification in PE 2025.12). So a primary
  # installed with peadm::install's r10k_known_hosts has it only in pe.conf.
  $pe_master_settings = $code_manager_read['_sensitive'].unwrap['settings']
  $pe_conf_path = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
  $code_manager_settings = ({
      'r10k_known_hosts' => $old_primary_pe_conf['puppet_enterprise::profile::master::r10k_known_hosts'],
  } + $pe_master_settings).filter |$_setting, $value| {
    !($value =~ Variant[Undef, String[0, 0], Collection[0, 0]])
  }
  $invalid_settings = $code_manager_types.keys.filter |$setting| {
    $setting in $code_manager_settings and !($code_manager_settings[$setting] =~ $code_manager_types[$setting])
  }
  unless empty($invalid_settings) {
    $invalid_descriptions = $invalid_settings.map |$setting| {
      $source = $setting in $pe_master_settings ? { true => 'the PE Master node group', default => $pe_conf_path }
      "puppet_enterprise::profile::master::${setting} in ${source} (expected ${code_manager_expected[$setting]})"
    }.join(', ')
    fail_plan(@("MSG"/L), 'peadm/invalid-code-manager-settings')
      These Code Manager settings on ${old_primary_host} have values of the wrong type: ${invalid_descriptions}. \
      Nothing has been changed: fix them on ${old_primary_host}, then run peadm::migrate again.
      |- MSG
  }
  $code_manager_not_carried = $code_manager_read['not_carried']
  $code_manager_not_carried.each |$setting| {
    out::message(@("MSG"/L))
      Warning: ${setting} is set on the old primary's PE Master node group but is not carried across. \
      Set it on the new primary after the migration.
      |- MSG
  }

  # The deploy key goes through the Bolt project's downloads directory, like
  # the backup below. The local copy is deleted whether or not the copy to the
  # new primary works.
  $deploy_key = $code_manager_settings['r10k_private_key']
  if $deploy_key {
    $key_download = download_file($deploy_key, 'code-manager-key', $old_primary_target, '_catch_errors' => true).first
    if $key_download.ok {
      # As peadm::install does. PE then gives the key to pe-puppet and, for
      # /etc/puppetlabs/puppetserver/ssh, sets the directory's owner and mode.
      $key_dir = run_command("mkdir -p ${shellquote(dirname($deploy_key))}", $new_primary_host, '_catch_errors' => true).first
      $key_upload = $key_dir.ok ? {
        true    => upload_file($key_download['path'], $deploy_key, $new_primary_host, '_catch_errors' => true).first,
        default => $key_dir,
      }
      $key_copy = $key_upload.ok ? {
        true    => run_command("chmod 0600 ${shellquote($deploy_key)}", $new_primary_host, '_catch_errors' => true).first,
        default => $key_upload,
      }
      file::delete($key_download['path'])
    } else {
      $key_copy = $key_download
    }
    unless $key_copy.ok {
      # A failed command's error message only gives the exit code; its output
      # says why.
      $key_copy_output = $key_copy['merged_output'] ? {
        String[1] => ": ${key_copy['merged_output'].strip}",
        default   => '',
      }
      fail_plan(@("MSG"/L), 'peadm/deploy-key-copy-failed')
        Could not copy the Code Manager deploy key ${deploy_key} from ${old_primary_host} to ${new_primary_host}. \
        Nothing has been backed up or installed yet, but the key or its directory may already be on ${new_primary_host}: \
        fix the cause, then run peadm::migrate again. Error: ${key_copy.error.message}${key_copy_output}
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
  # Where peadm::restore unpacks it.
  $remote_backup_directory = "/tmp/${basename($backup_filename, '.tar.gz')}"

  upload_file($download_path, $remote_backup_path, $new_primary_host)

  # Say where every copy of the backup is now, so the output has it even if a
  # later step fails. Nothing is deleted then (PE-48753).
  $backup_copies = "${old_primary_host}:${backup_file['path']}, this machine:${download_path}, ${new_primary_host}:${remote_backup_path}"
  out::message(@("MSG"/L))
    The migration backup holds PE secrets. Copies: ${backup_copies}. \
    If the migration succeeds, the last two are deleted unless keep_backup is true.
    |- MSG

  $old_primary_password = $old_primary_pe_conf['console_admin_password']
  $old_peadm_config = run_task('peadm::get_peadm_config', $old_primary_target).first.value

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

  run_plan('peadm::install', {
      primary_host                => $new_primary_host,
      console_password            => $old_primary_password,
      code_manager_auto_configure => true,
      download_mode               => $download_mode,
      pe_installer_source         => $pe_installer_source,
      version                     => $old_peadm_config['pe_version'],
      license_key_content         => $install_license_content,
      pe_conf_data                => Hash($code_manager_settings.map |$setting, $value| {
          ["puppet_enterprise::profile::master::${setting}", $value]
      }),
  })

  run_plan('peadm::restore', {
      targets          => $new_primary_host,
      restore_type     => 'migration',
      input_file       => $remote_backup_path,
      console_password => $old_primary_password,
  })

  $node_types = {
    'primary_host'             => $old_peadm_config['params']['primary_host'],
    'replica_host'             => $old_peadm_config['params']['replica_host'],
    'primary_postgresql_host'  => $old_peadm_config['params']['primary_postgresql_host'],
    'replica_postgresql_host'  => $old_peadm_config['params']['replica_postgresql_host'],
    'compilers'                => $old_peadm_config['params']['compilers'],
    'legacy_compilers'         => $old_peadm_config['params']['legacy_compilers'],
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
    # TODO PE-48752: add_replica does not copy the Code Manager deploy key to the replica.
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
  unless empty($code_manager_not_carried) {
    out::message(@("MSG"/L))
      Warning: migration finished, but these Code Manager settings on the old primary were not carried across: \
      ${code_manager_not_carried.join(', ')}. Set them on the new primary.
      |- MSG
  }

  # The migration has succeeded, so delete the backup copies it made (PE-48753).
  # The old primary's copy is the operator's to keep or delete.
  if $keep_backup {
    out::message(@("MSG"/L))
      Kept the migration backup copies, as keep_backup is true: ${backup_copies}. \
      They hold PE secrets: delete them once you no longer need them.
      |- MSG
  } else {
    $local_cleanup = catch_errors() || { file::delete($download_path) }
    if $local_cleanup =~ Error {
      $local_cleanup_failure = ["this machine:${download_path} (${local_cleanup.message})"]
    } else {
      out::message("Removed the migration backup copy ${download_path} on this machine.")
      $local_cleanup_failure = []
    }

    $remote_cleanup = run_command(
      "rm -rf ${shellquote($remote_backup_path)} ${shellquote($remote_backup_directory)}",
      $new_primary_host,
      '_catch_errors' => true,
    ).first
    if $remote_cleanup.ok {
      out::message("Removed the migration backup copies ${remote_backup_path} and ${remote_backup_directory} on ${new_primary_host}.")
      $remote_cleanup_failure = []
    } else {
      # A failed command's error message only gives the exit code; its output
      # says why.
      $remote_cleanup_output = $remote_cleanup['merged_output'] ? {
        String[1] => ": ${remote_cleanup['merged_output'].strip}",
        default   => '',
      }
      $remote_cleanup_failure = [
        "${new_primary_host}:${remote_backup_path} and ${remote_backup_directory} (${remote_cleanup.error.message}${remote_cleanup_output})",
      ]
    }

    out::message(@("MSG"/L))
      The old primary's migration backup is still at ${old_primary_host}:${backup_file['path']}. \
      It holds PE secrets: delete it, or archive it somewhere safe.
      |- MSG

    $cleanup_failures = $local_cleanup_failure + $remote_cleanup_failure
    unless empty($cleanup_failures) {
      fail_plan(@("MSG"/L), 'peadm/backup-cleanup-failed')
        Migration finished, but these migration backup copies could not be deleted: ${cleanup_failures.join('; ')}. \
        They hold PE secrets: delete them yourself.
        |- MSG
    }
  }
}
