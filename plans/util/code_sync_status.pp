# @api private
plan peadm::util::code_sync_status (
  Peadm::SingleTargetSpec $targets,
) {
  $data = run_task('peadm::code_sync_status', $targets).first.value

  # Print a table of summary status
  out::message(
    format::table({
        title => 'Summary',
        rows  => $data['environments'].reduce([['Overall sync status', $data['sync']]]) |$memo, $val| {
  $memo << ["${val[0]} environment in sync", $val[1]['sync']] } }))

  # Print a server status table, one for each environment
  $data['environments'].each |$env, $_| {
    out::message(
      format::table({
          title => "Server sync status - ${env}",
          head  => ['Server', 'In Sync', 'Commit'],
          rows  => $data['environments'][$env]['servers'].reduce([]) |$memo, $val| {
    $memo << [$val[0], $val[1]['sync'], $val[1]['commit']] } }))
  }

  return('Done')
}
