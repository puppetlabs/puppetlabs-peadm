# @api private
plan peadm::util::copy_file(
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $source_host,
  Stdlib::Absolutepath    $path
) {
  $source_target   = peadm::get_targets($source_host, 1)
  $replica_target  = $targets

  # Callers copy the orchestrator's keys.json and
  # orchestrator-encryption-keys.json and console-services' keys.json, so
  # read as Sensitive (PE-47523)
  $source_content = peadm::read_sensitive_file($source_target, $path)

  if $source_content {
    run_task('peadm::mkdir_p_file', $replica_target,
      path    => $path,
      owner   => 'root',
      group   => 'root',
      # TODO PE-47900: this makes the copied secret files world-readable on the replica.
      mode    => '0644',
      content => $source_content.unwrap,
    )
  } else {
    out::message("Skipping file copy: ${path} on ${source_target.peadm::certname()} had no content")
  }
}
