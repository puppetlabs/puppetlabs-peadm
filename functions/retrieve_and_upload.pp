function pe_xl::retrieve_and_upload(
  $source,
  $local_path,
  $upload_path,
  $target,
) {
  $exists = without_default_logging() || {
    run_command("test -e '${local_path}'", 'local://localhost',
      _catch_errors => true,
    ).ok()
  }

  unless $exists {
    run_task('pe_xl::download', 'local://localhost',
      source => $source,
      path   => $local_path,
    )
  }

  $size = run_command("stat -c%s '${local_path}' 2>/dev/null", 'local://localhost').first.value['stdout'].chomp

  $targets_needing_file = run_task('pe_xl::filesize', $target,
    path => $upload_path,
  ).filter |$task| {
    $task['_output'].chomp != $size
  }.map |$task| {
    $task.target
  }

  upload_file($local_path, $upload_path, $targets_needing_file)
}
