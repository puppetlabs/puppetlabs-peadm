plan peadm::util::db_disable_pglogical(
  Peadm::SingleTargetSpec $targets,
  Array[String[1]]        $databases,
) {

  $databases.each |$database| {
    run_command( "runuser -u pe-postgres -- \
      /opt/puppetlabs/server/bin/psql \"${database}\" -c 'DROP EXTENSION IF EXISTS pglogical'",
      $targets
    )
  }
  run_command('systemctl restart pe-postgresql', $targets)
}
