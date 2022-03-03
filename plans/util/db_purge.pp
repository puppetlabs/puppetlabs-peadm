plan peadm::util::db_purge(
  TargetSpec       $targets,
  Array[String[1]] $databases,
) {

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
