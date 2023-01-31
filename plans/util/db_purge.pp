# @api private
plan peadm::util::db_purge(
  TargetSpec       $targets,
  Array[String[1]] $databases,
) {
  # Their are more sophisticated ways to clean up these databases so they do not
  # continue taking up disk space but they are finicky and grow complex. Instead
  # just delete them even though Puppet will recreate them on the next agent run.
  $databases.each |$database| {
    run_command( "runuser -u pe-postgres -- \
        /opt/puppetlabs/server/bin/psql pe-postgres -c 'DROP DATABASE IF EXISTS \"${database}\"'",
      $targets
    )
    run_command("runuser -u pe-postgres -- \
        /opt/puppetlabs/server/bin/psql pe-postgres -c 'DROP TABLESPACE IF EXISTS \"${database}\"'",
      $targets
    )
  }
}
