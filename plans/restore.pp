# @api private
# @summary Restore the core user settings for puppet infrastructure from backup
#
# This plan can restore data to puppet infrastructure for DR and rebuilds
# 
# TODO
# - make sure restore tries to leave the system in a running state if possible
# - merge the restore of certs, config and code scope to one puppet-backup restore command
plan peadm::restore (
  # This plan should be run on the primary server
  Peadm::SingleTargetSpec $targets,

  # Which data to restore
  Peadm::Recovery_opts    $restore = {},

  # Path to the recovery tarball
  Pattern[/.*\.tar\.gz$/] $input_file,

  # Do we want to merge existing puppetdb content to the restored content?
  Boolean $merge_puppetdb = false,
) {
  peadm::assert_supported_bolt_version()

  $recovery_opts = (peadm::recovery_opts_default() + $restore)
  $recovery_directory = "${dirname($input_file)}/${basename($input_file, '.tar.gz')}"

  # try to load the cluster configuration by running peadm::get_peadm_config, but allow for errors to happen
  $_cluster = run_task('peadm::get_peadm_config', $targets, { '_catch_errors' => true }).first.value
  if $_cluster == undef {
    # failed to get cluster config, load from backup
    out::message('Failed to get cluster configuration, loading from backup...')
    $result = download_file("${recovery_directory}/peadm/peadm_config.json", 'peadm_config.json', $targets).first.value
    $cluster = loadjson(getvar('result.path'))
    out::message('Cluster configuration loaded from backup')
  } else {
    $cluster = $_cluster
  }

  $arch = peadm::assert_supported_architecture(
    getvar('cluster.params.primary_host'),
    getvar('cluster.params.replica_host'),
    getvar('cluster.params.primary_postgresql_host'),
    getvar('cluster.params.replica_postgresql_host'),
    getvar('cluster.params.compiler_hosts'),
  )

  $primary_target   = peadm::get_targets(getvar('cluster.params.primary_host'), 1)
  $replica_target   = peadm::get_targets(getvar('cluster.params.replica_host'), 1)
  $compiler_targets = peadm::get_targets(getvar('cluster.params.compiler_hosts'))

  # Determine the array of targets to which the PuppetDB PostgreSQL database
  # should be restored to. This could be as simple as just the primary server,
  # or it could be two separate PostgreSQL servers.
  $puppetdb_postgresql_targets = peadm::flatten_compact([
      getvar('cluster.params.primary_postgresql_host') ? {
        undef   => $primary_target,
        default => peadm::get_targets(getvar('cluster.params.primary_postgresql_host'), 1),
      },
      getvar('cluster.params.replica_postgresql_host') ? {
        undef   => $replica_target,
        default => peadm::get_targets(getvar('cluster.params.replica_postgresql_host'), 1),
      },
  ])

  $puppetdb_targets = peadm::flatten_compact([
      $primary_target,
      $replica_target,
      $compiler_targets,
  ])

# lint:ignore:strict_indent
  run_command(@("CMD"/L), $primary_target)
    umask 0077 \
      && cd ${shellquote(dirname($recovery_directory))} \
      && tar -xzf ${shellquote($input_file)}
    | CMD
# lint:endignore
  # Map of recovery option name to array of database hosts to restore the
  # relevant .dump content to.
  $restore_databases = {
    'orchestrator' => [$primary_target],
    'activity'     => [$primary_target],
    'rbac'         => [$primary_target],
    'puppetdb'     => $puppetdb_postgresql_targets,
  }.filter |$key,$_| {
    $recovery_opts[$key] == true
  }

  if getvar('recovery_opts.classifier') {
    out::message('# Restoring classification')
    run_task('peadm::backup_classification', $primary_target,
      directory => $recovery_directory
    )

    run_task('peadm::transform_classification_groups', $primary_target,
      source_directory  => "${recovery_directory}/classifier",
      working_directory => $recovery_directory
    )

    run_task('peadm::restore_classification', $primary_target,
      classification_file => "${recovery_directory}/transformed_classification.json",
    )
  }

  if getvar('recovery_opts.ca') {
    out::message('# Restoring ca and ssl certificates')
# lint:ignore:strict_indent
    run_command(@("CMD"/L), $primary_target)
      /opt/puppetlabs/bin/puppet-backup restore \
        --scope=certs \
        --tempdir=${shellquote($recovery_directory)} \
        --force \
        ${shellquote($recovery_directory)}/ca/pe_backup-*tgz
      | CMD
  }

  if getvar('recovery_opts.code') {
    out::message('# Restoring code')
    run_command(@("CMD"/L), $primary_target)
      /opt/puppetlabs/bin/puppet-backup restore \
        --scope=code \
        --tempdir=${shellquote($recovery_directory)} \
        --force \
        ${shellquote($recovery_directory)}/code/pe_backup-*tgz
      | CMD
  }

  if getvar('recovery_opts.config') {
    out::message('# Restoring config')
    run_command(@("CMD"/L), $primary_target)
      /opt/puppetlabs/bin/puppet-backup restore \
        --scope=config \
        --tempdir=${shellquote($recovery_directory)} \
        --force \
        ${shellquote($recovery_directory)}/config/pe_backup-*tgz
      | CMD
  }

  # Use PuppetDB's /pdb/admin/v1/archive API to SAVE data currently in PuppetDB.
  # Otherwise we'll completely lose it if/when we restore.
  # TODO: consider adding a heuristic to skip when innappropriate due to size
  #       or other factors.
  if getvar('recovery_opts.puppetdb') and $merge_puppetdb {
    out::message('# Exporting puppetdb')
    run_command(@("CMD"/L), $primary_target)
      /opt/puppetlabs/bin/puppet-db export \
        --cert=$(/opt/puppetlabs/bin/puppet config print hostcert) \
        --key=$(/opt/puppetlabs/bin/puppet config print hostprivkey) \
        ${shellquote($recovery_directory)}/puppetdb-archive.bin
      | CMD
  }

  ## shutdown services
  run_command(@("CMD"/L), $primary_target)
    systemctl stop pe-console-services pe-nginx pxp-agent pe-puppetserver \
                   pe-orchestration-services puppet pe-puppetdb
    | CMD

  # Restore secrets/keys.json if it exists
  out::message('# Restoring ldap secret key if it exists')
  run_command(@("CMD"/L), $primary_target)
    test -f ${shellquote($recovery_directory)}/rbac/keys.json \
      && cp -rp ${shellquote($recovery_directory)}/keys.json /etc/puppetlabs/console-services/conf.d/secrets/ \
      || echo secret ldap key doesn\'t exist
    | CMD
# lint:ignore:140chars
  # IF restoring orchestrator restore the secrets to /etc/puppetlabs/orchestration-services/conf.d/secrets/
  if getvar('recovery_opts.orchestrator') {
    out::message('# Restoring orchestrator secret keys')
    run_command(@("CMD"/L), $primary_target)
      cp -rp ${shellquote($recovery_directory)}/orchestrator/secrets/* /etc/puppetlabs/orchestration-services/conf.d/secrets/ 
      | CMD
  }
# lint:endignore

  #$database_to_restore.each |Integer $index, Boolean $value | {
  $restore_databases.each |$name,$database_targets| {
    out::message("# Restoring ${name} database")
    $dbname = "pe-${shellquote($name)}"

    # Drop pglogical extensions and schema if present
    run_command(@("CMD"/L), $database_targets)
      su - pe-postgres -s /bin/bash -c \
        "/opt/puppetlabs/server/bin/psql \
           --tuples-only \
           -d '${dbname}' \
           -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'"
      | CMD

    run_command(@("CMD"/L), $database_targets)
      su - pe-postgres -s /bin/bash -c \
        "/opt/puppetlabs/server/bin/psql \
           -d '${dbname}' \
           -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'"
      | CMD

    # To allow db user to restore the database grant temporary privileges
    run_command(@("CMD"/L), $database_targets)
      su - pe-postgres -s /bin/bash -c \
        "/opt/puppetlabs/server/bin/psql \
           -d '${dbname}' \
           -c 'ALTER USER \"${dbname}\" WITH SUPERUSER;'"
      | CMD

    # Restore database. If there are multiple database restore targets, perform
    # the restore(s) in parallel.
    parallelize($database_targets) |$database_target| {
      run_command(@("CMD"/L), $primary_target)
        /opt/puppetlabs/server/bin/pg_restore \
          -j 4 \
          -d "sslmode=verify-ca \
              host=${shellquote($database_target.peadm::certname())} \
              sslcert=/etc/puppetlabs/puppetdb/ssl/${shellquote($primary_target.peadm::certname())}.cert.pem \
              sslkey=/etc/puppetlabs/puppetdb/ssl/${shellquote($primary_target.peadm::certname())}.private_key.pem \
              sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem \
              dbname=${dbname} \
              user=${dbname}" \
          -Fd ${recovery_directory}/${name}/${dbname}.dump.d
        | CMD
    }

    # Remove db user privileges post restore
    run_command(@("CMD"/L), $database_targets)
      su - pe-postgres -s /bin/bash -c \
        "/opt/puppetlabs/server/bin/psql \
           -d '${dbname}' \
           -c 'ALTER USER \"${dbname}\" WITH NOSUPERUSER;'"
      | CMD

    # Drop pglogical extension and schema (again) if present after db restore
    run_command(@("CMD"/L), $database_targets)
      su - pe-postgres -s /bin/bash -c \
        "/opt/puppetlabs/server/bin/psql \
           --tuples-only \
           -d '${dbname}' \
           -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'"
      | CMD

    run_command(@("CMD"/L), $database_targets)
      su - pe-postgres -s /bin/bash -c \
        "/opt/puppetlabs/server/bin/psql \
           -d '${dbname}' \
           -c 'DROP EXTENSION IF EXISTS pglogical CASCADE;'"
      | CMD
  }

  # Use `puppet infra` to ensure correct file permissions, restart services,
  # etc. Make sure not to try and get config data from the classifier, which
  # isn't yet up and running.
  run_command(@("CMD"/L), $primary_target)
    /opt/puppetlabs/bin/puppet-infrastructure configure --no-recover
    | CMD

  # If we have replicas reinitalise them
  run_command(@("CMD"/L), $replica_target)
    /opt/puppetlabs/bin/puppet-infra reinitialize replica -y
    | CMD

  # Use PuppetDB's /pdb/admin/v1/archive API to MERGE previously saved data
  # into the restored database.
  # TODO: consider adding a heuristic to skip when innappropriate due to size
  #       or other factors.
  if getvar('recovery_opts.puppetdb') and $merge_puppetdb {
    run_command(@("CMD"/L), $primary_target)
      /opt/puppetlabs/bin/puppet-db import \
      --cert=$(/opt/puppetlabs/bin/puppet config print hostcert) \
      --key=$(/opt/puppetlabs/bin/puppet config print hostprivkey) \
      ${shellquote($recovery_directory)}/puppetdb-archive.bin
      | CMD
# lint:endignore
  }

  # Run Puppet to pick up last remaining config tweaks
  run_task('peadm::puppet_runonce', $primary_target)

  apply($primary_target) {
    file { $recovery_directory :
      ensure => 'absent',
      force  => true,
    }
  }

  return('success')
}
