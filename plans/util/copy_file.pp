# @api private
plan peadm::util::copy_file(
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $source_host,
  Stdlib::Absolutepath    $path
) {
  $source_target   = peadm::get_targets($source_host, 1)
  $replica_target  = $targets

  $source_content = run_task('peadm::read_file', $source_target,
    path => $path
  ).first['content']

  if $source_content {
    run_task('peadm::mkdir_p_file', $replica_target,
      path    => $path,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => $source_content,
    )
  } else {
    out::message("Skipping file copy: ${path} on ${source_target.peadm::certname()} had no content")
  }
}
