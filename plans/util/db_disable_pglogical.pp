# @api private
plan peadm::util::db_disable_pglogical(
  Peadm::SingleTargetSpec $targets,
  Array[String[1]]        $databases,
) {
  # Simplest way to disable the connection that the pglogical supervisor opens
  # to each database it means to replicate.
  $databases.each |$database| {
    run_command( "runuser -u pe-postgres -- \
      /opt/puppetlabs/server/bin/psql \"${database}\" -c 'DROP EXTENSION IF EXISTS pglogical'",
      $targets
    )
  }

  # Reload does not work to shutdown the connection post extension removal, must restart
  run_command('systemctl restart pe-postgresql', $targets)
}
