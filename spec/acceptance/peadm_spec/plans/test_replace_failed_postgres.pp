plan peadm_spec::test_replace_failed_postgres(
  Peadm::SingleTargetSpec   $primary_host,
  Peadm::SingleTargetSpec   $replica_host,
  Peadm::SingleTargetSpec   $working_postgresql_host,
  Peadm::SingleTargetSpec   $failed_postgresql_host,
  Peadm::SingleTargetSpec   $replacement_postgresql_host,
) {
  wait_until_available($primary_host)
  wait_until_available($replica_host)
  wait_until_available($working_postgresql_host)
  wait_until_available($failed_postgresql_host)
  wait_until_available($replacement_postgresql_host)

  out::message("Primary host: ${primary_host}")
  out::message("Replica host: ${replica_host}")
  out::message("Working PostgreSQL host: ${working_postgresql_host}")
  out::message("Failed PostgreSQL host: ${failed_postgresql_host}")
  out::message("Replacement PostgreSQL host: ${replacement_postgresql_host}")

  $primary_fqdn = run_command('hostname -f', $primary_host).first['stdout'].chomp
  $replica_fqdn = run_command('hostname -f', $replica_host).first['stdout'].chomp
  $working_postgres_fqdn = run_command('hostname -f', $working_postgresql_host).first['stdout'].chomp
  $failed_postgres_fqdn = run_command('hostname -f', $failed_postgresql_host).first['stdout'].chomp
  $replacement_postgres_fqdn = run_command('hostname -f', $replacement_postgresql_host).first['stdout'].chomp

  out::message("Primary host: ${primary_host}, fqdn: ${primary_fqdn}")
  out::message("Replica host: ${replica_host}, fqdn: ${replica_fqdn}")
  out::message("Working PostgreSQL host: ${working_postgresql_host}, fqdn: ${working_postgres_fqdn}")
  out::message("Failed PostgreSQL host: ${failed_postgresql_host}, fqdn: ${failed_postgres_fqdn}")
  out::message("Replacement PostgreSQL host: ${replacement_postgresql_host}, fqdn: ${replacement_postgres_fqdn}")

  run_plan('peadm::replace_failed_postgresql',
    primary_host => $primary_host,
    replica_host => $replica_host,
    working_postgresql_host => $working_postgresql_host,
    failed_postgresql_host => $failed_postgresql_host,
    replacement_postgresql_host => $replacement_postgresql_host,
  )
}
