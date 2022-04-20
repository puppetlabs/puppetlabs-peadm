# @summary Restore the core user settings for puppet infrastructure from backup
#
# This plan can restore data to puppet infrastructure for DR and rebuilds
# 
plan peadm::restore (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  # Which data to restore
  Boolean                            $restore_orchestrator    = true,
  Boolean                            $restore_rbac            = true,
  Boolean                            $restore_activity        = true,
  Boolean                            $restore_ca_ssl          = true,
  Boolean                            $restore_puppetdb        = false,
  Boolean                            $restore_classification  = true,
  String                             $input_directory         = '/tmp',
  String                             $working_directory       = '/tmp',
  String                             $backup_timestamp,
){
  peadm::assert_supported_bolt_version()
  $cluster = run_task('peadm::get_peadm_config', $primary_host).first.value

  $arch = peadm::assert_supported_architecture(
    $primary_host,
    $cluster['params']['replica_host'],
    $cluster['params']['primary_postgresql_host'],
    $cluster['params']['replica_postgresql_host'],
    $cluster['params']['compiler_hosts'],
  )
  $servers = delete_undef_values([$primary_host , $cluster['params']['replica_host'] ])
  $cluster_servers = delete_undef_values($servers + $cluster['params']['compiler_hosts'] + [ $cluster['params']['primary_postgresql_host'], $cluster['params']['replica_postgresql_host']]) # lint:ignore:140chars
  if $cluster['params']['compiler_hosts'] {
    $check_puppetdb_on_compilers = run_task('service', $cluster['params']['compiler_hosts'],
      action => 'status',
      name   => 'pe-puppetdb'
    )
    $puppetdb_on_compilers = $check_puppetdb_on_compilers.filter_set | $result | {
      $result['enabled'] == 'enabled'
    }.targets
  } else {
    $puppetdb_on_compilers = undef
  }
  $puppetdb_servers = delete_undef_values([$servers,$puppetdb_on_compilers])
  $backup_directory = "${input_directory}/pe-backup-${backup_timestamp}"
  $database_backup_directory = "${working_directory}/pe-backup-databases-${backup_timestamp}"
  # I need the actual hostname for the certificate in a remote puppetdb backup. If a user sends primary host as IP it will fail
  $primary_host_fqdn = $cluster['params']['primary_host']
  $primary_postgresql_host = $cluster['params']['primary_postgresql_host']
  apply($primary_host){
    file { $database_backup_directory :
      ensure => 'directory',
      owner  => 'pe-puppetdb',
      group  => 'pe-postgres',
      mode   => '0770'
    }
  }

  # Create an array of the names of databases and whether they have to be backed up to use in a lambda later
  $database_to_restore = [ $restore_orchestrator, $restore_activity, $restore_rbac, $restore_puppetdb]
  $database_names      = [ 'pe-orchestrator' , 'pe-activity' , 'pe-rbac' , 'pe-puppetdb' ]

  peadm::assert_supported_bolt_version()

  if $restore_classification {

    out::message('# Restoring classification')
    run_task('peadm::backup_classification', $primary_host,
      directory => $working_directory
    )
    out::message("# Backed up current classification to ${working_directory}/classification_backup.json")

    run_task('peadm::transform_classification_groups', $primary_host,
      source_directory => $backup_directory,
      working_directory => $working_directory
    )

    run_task('peadm::restore_classification', $primary_host,
    classification_file => "${working_directory}/classification_backup.json",
    )
  }

  if $restore_ca_ssl {
    out::message('# Restoring ca and ssl certificates')
    run_command("/opt/puppetlabs/bin/puppet-backup restore ${backup_directory}/pe_backup-*tgz --scope=certs --tempdir=${working_directory} --force", $primary_host) # lint:ignore:140chars
  }

  ## shutdown services
    run_task('service', $servers,
      action => 'stop',
      name   => 'pe-console-services'
    )
    run_task('service', $primary_host,
      action => 'stop',
      name   => 'pe-nginx'
    )
    run_task('service', $servers,
      action => 'stop',
      name   => 'pe-puppetserver'
    )
    run_task('service', $servers,
      action => 'stop',
      name   => 'pxp-agent'
    )
    run_task('service', $primary_host,
      action => 'stop',
      name   => 'pe-orchestration-services'
    )
    run_task('service', $cluster_servers,
      action => 'stop',
      name   => 'puppet'
    )
    run_task('service', $puppetdb_servers ,
      action => 'stop',
      name   => 'pe-puppetdb'
    )


  # Restore secrets/keys.json if it exists
  out::message('# Restoring ldap secret key if it exists')
  run_command("test -f ${backup_directory}//keys.json && cp -rp ${backup_directory}/keys.json /etc/puppetlabs/console-services/conf.d/secrets/ || echo secret ldap key doesnt exist" , $primary_host) # lint:ignore:140chars

  # IF restoring orchestrator restore the secrets too /etc/puppetlabs/orchestration-services/conf.d/secrets/
  if $restore_orchestrator {
    out::message('# Restoring orchestrator secret keys')
    run_command("cp -rp ${backup_directory}/secrets/* /etc/puppetlabs/orchestration-services/conf.d/secrets ", $primary_host)
  }

  $database_to_restore.each |Integer $index, Boolean $value | {
    if $value {
    out::message("# Restoring database ${database_names[$index]}")
      # If the primary postgresql host is set then pe-puppetdb needs to be remotely backed up to primary.
      if $database_names[$index] == 'pe-puppetdb' and $primary_postgresql_host {
        # Drop pglogical extensions and schema if present
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql --tuples-only -d '${database_names[$index]}' -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"", $primary_postgresql_host) # lint:ignore:140chars
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql -d '${database_names[$index]}' -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'\"", $primary_postgresql_host) # lint:ignore:140chars
        # To allow pe-puppetdb to restore the database grant temporary privileges
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql -d '${database_names[$index]}' -c 'ALTER USER \\\"pe-puppetdb\\\" WITH SUPERUSER;'\"", $primary_postgresql_host) # lint:ignore:140chars
        # Restore database
        run_command("/opt/puppetlabs/server/bin/pg_restore -d \"sslmode=verify-ca host=${primary_postgresql_host} sslcert=/etc/puppetlabs/puppetdb/ssl/${primary_host_fqdn}.cert.pem sslkey=/etc/puppetlabs/puppetdb/ssl/${primary_host_fqdn}.private_key.pem sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem dbname=pe-puppetdb user=pe-puppetdb\" -Fd ${backup_directory}/puppetdb_*" , $primary_host) # lint:ignore:140chars
        # Remove pe-puppetdb privileges post restore
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql -d '${database_names[$index]}' -c 'ALTER USER \\\"pe-puppetdb\\\" WITH NOSUPERUSER;'\"", $primary_postgresql_host) # lint:ignore:140chars
        # Drop pglogical extension and schema (again) if present after db restore
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql --tuples-only -d '${database_names[$index]}' -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"",$primary_postgresql_host) # lint:ignore:140chars
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql -d '${database_names[$index]}' -c 'DROP EXTENSION IF EXISTS pglogical CASCADE;;'\"",$primary_postgresql_host) # lint:ignore:140chars
      } else {
        # Drop pglogical extensions and schema if present
        run_command("su - pe-postgres -s '/bin/bash' -c \"/opt/puppetlabs/server/bin/psql --tuples-only -d '${database_names[$index]}' -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"", $primary_host) # lint:ignore:140chars
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql -d '${database_names[$index]}' -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'\"", $primary_host) # lint:ignore:140chars
        # Restore database
        run_command("cp -pr ${backup_directory}/${database_names[$index]}_* ${database_backup_directory}/ ", $primary_host )
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/pg_restore ${database_backup_directory}/${database_names[$index]}_* -Fd -j4 --dbname=${database_names[$index]}\"", $primary_host)# lint:ignore:140chars
        run_command("sudo -H -u pe-postgres /opt/puppetlabs/server/bin/pg_restore -d ${database_names[$index]} -c ${database_backup_directory}/${database_names[$index]}_*",$primary_host) # lint:ignore:140chars
        run_command("rm -rf ${database_backup_directory}/${database_names[$index]}_*", $primary_host )
        # Drop pglogical extension and schema (again) if present after db restore
        run_command("su - pe-postgres -s '/bin/bash' -c \"/opt/puppetlabs/server/bin/psql --tuples-only -d '${database_names[$index]}' -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"",$primary_host) # lint:ignore:140chars
        run_command("su - pe-postgres -s /bin/bash -c \"/opt/puppetlabs/server/bin/psql -d '${database_names[$index]}' -c 'DROP EXTENSION IF EXISTS pglogical CASCADE;'\"",$primary_host) # lint:ignore:140chars
      }
    }
  }

  ## Restart services
  run_task('service', $primary_host,
    action => 'start',
    name   => 'pe-orchestration-services'
  )
  run_task('service', $servers,
    action => 'start',
    name   => 'pxp-agent'
  )
  run_task('service', $servers,
    action => 'start',
    name   => 'pe-puppetserver'
  )
  run_task('service', $primary_host,
    action => 'start',
    name   => 'pe-nginx'
  )
  run_task('service', $servers,
    action => 'start',
    name   => 'pe-console-services'
  )
  run_task('service', $cluster_servers,
    action => 'start',
    name   => 'puppet'
  )
  run_task('service', $puppetdb_servers,
    action => 'start',
    name   => 'pe-puppetdb'
  )
# If we have replicas reinitalise any databases restored
  if $cluster['params']['replica_host'] {
    $database_to_restore.each |Integer $index, Boolean $value | {
      if $database_names[$index] != 'pe-puppetdb' and $cluster['params']['replica_postgresql_host'] {
        run_command("/opt/puppetlabs/bin/puppet-infra reinitialize replica --db ${database_names[$index]} -y", $cluster['params']['replica_host'] ) # lint:ignore:140chars
      }
    }
  }

  apply($primary_host){
    file { $database_backup_directory :
      ensure => 'absent',
      force  => true
    }
  }
}
