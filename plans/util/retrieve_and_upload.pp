plan peadm::util::retrieve_and_upload(
  TargetSpec $nodes,
  String[1]  $source,
  String[1]  $local_path,
  String[1]  $upload_path,
) {
  $exists = without_default_logging() || {
    run_command("test -e '${local_path}'", 'local://localhost',
      _catch_errors => true,
    ).ok()
  }

  unless $exists {
    run_task('peadm::download', 'local://localhost',
      source => $source,
      path   => $local_path,
    )
  }

  $local_size = run_task('peadm::filesize', 'local://localhost',
    path => $local_path,
  ).first['size']

  $targets_needing_file = run_task('peadm::filesize', $nodes,
    path => $upload_path,
  ).filter |$result| {
    $result['size'] != $local_size
  }.map |$result| {
    $result.target
  }

  upload_file($local_path, $upload_path, $targets_needing_file)
}
