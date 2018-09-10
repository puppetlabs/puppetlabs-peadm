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

  upload_file($local_path, $upload_path, $target)
}
