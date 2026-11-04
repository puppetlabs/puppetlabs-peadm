# @api private
#
# @summary Check that a PE installer can be fetched the same way a later
#   install or upgrade will fetch it, so a bad URL or missing network access
#   fails the plan before anything has been changed.
#
# @param targets
#   The hosts that download the installer themselves when download_mode is
#   'direct'. Unused for 'bolthost', where only the Bolt host downloads it.
# @param source
#   URL of the installer.
# @param tarball_name
#   File name of the installer, used in messages instead of the full URL,
#   which may carry credentials.
# @param download_mode
#   Where the installer will be downloaded: on the Bolt host ('bolthost') or
#   on each of the targets ('direct').
# @param stagingdir
#   Where the Bolt host keeps installers in 'bolthost' mode. A file already
#   staged there is used as-is, so no download check is needed.
plan peadm::util::check_installer_source(
  TargetSpec           $targets,
  String[1]            $source,
  String[1]            $tarball_name,
  Peadm::Download_mode $download_mode,
  String[1]            $stagingdir = '/tmp',
) {
  if $download_mode == 'bolthost' {
    $bolthost_os = run_task('peadm::os_identification', 'local://localhost').first.value['_output']
    if 'windows' in $bolthost_os {
      out::message("Skipping the download check for ${tarball_name}: it isn't supported on Windows Bolt hosts")
      return()
    }

    $staged = without_default_logging() || {
      run_command("test -e ${shellquote("${stagingdir}/${tarball_name}")}", 'local://localhost',
        _catch_errors => true,
      ).ok
    }
    if $staged {
      out::message("Using the PE installer already staged at ${stagingdir}/${tarball_name}")
      return()
    }

    $check_targets = get_targets('local://localhost')
    $where = 'the Bolt host'
  } else {
    $check_targets = get_targets($targets)
    $where = $check_targets.map |$t| { $t.name }.join(', ')
  }

  # A HEAD request, as tasks/download.sh makes, rather than downloading
  # about 1 GB. The URL goes in an environment variable, not the command
  # line, so it doesn't appear in Bolt's output.
  # lint:ignore:single_quote_string_with_variables
  $results = run_command('curl -sSfIL -o /dev/null "$PEADM_INSTALLER_SOURCE"', $check_targets,
    _catch_errors => true,
    _env_vars     => { 'PEADM_INSTALLER_SOURCE' => $source },
  )
  # lint:endignore

  unless $results.ok {
    $errors = $results.error_set.map |$r| {
      $stderr = String($r['stderr']).strip
      $download_mode ? { 'bolthost' => $stderr, default => "${r.target.name}: ${stderr}" }
    }.join('; ')
    # lint:ignore:strict_indent
    fail_plan(@("MSG"/L))
      Can't download the PE installer ${tarball_name} from ${where} (${errors}). \
      Nothing has been changed. Check the installer URL and that ${where} can \
      reach it, or pre-stage the installer in ${stagingdir} on the Bolt host \
      and use download_mode=bolthost.
      |-MSG
    # lint:endignore
  }
}
