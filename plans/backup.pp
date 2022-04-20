# @summary Backup the core user settings for puppet infrastructure
#
# This plan can backup data as outlined at insert doc
# 
plan peadm::backup (
  # This plan should be run on the primary server
  Peadm::SingleTargetSpec $targets,

  # Which data to backup
  Peadm::Recovery_opts    $backup = {},

  # Where to put the backup folder
  String                  $output_directory = '/tmp',
) {
  peadm::assert_supported_bolt_version()

  $recovery_opts = (peadm::recovery_opts_default() + $backup)
  $cluster = run_task('peadm::get_peadm_config', $targets).first.value
  $arch = peadm::assert_supported_architecture(
    getvar('cluster.params.primary_host'),
    getvar('cluster.params.replica_host'),
    getvar('cluster.params.primary_postgresql_host'),
    getvar('cluster.params.replica_postgresql_host'),
    getvar('cluster.params.compiler_hosts'),
  )

  $timestamp = Timestamp.new().strftime('%Y-%m-%dT%H%M%SZ')
  $backup_directory = "${output_directory}/pe-backup-${timestamp}"

  $primary_target = getvar('cluster.params.primary_host')
  $puppetdb_postgresql_target = getvar('cluster.params.primary_postgresql_host') ? {
    undef   => getvar('cluster.params.primary_host'),
    default => getvar('cluster.params.primary_postgresql_host'),
  }

  $backup_databases = {
    'orchestrator' => $primary_target,
    'activity'     => $primary_target,
    'rbac'         => $primary_target,
    'puppetdb'     => $puppetdb_postgresql_target,
  }.filter |$key,$_| {
    $recovery_opts[$key] == true
  }

  # Create backup folders
  apply($primary_target) {
    file { $backup_directory :
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => '0700'
    }

    # Create a subdir for each backup type selected
    $recovery_opts.filter |$_,$val| { $val == true }.each |$dir,$_| {
      file { "${backup_directory}/${dir}":
        ensure => 'directory',
        owner  => 'root',
        group  => 'root',
        mode   => '0700'
      }
    }
  }

  if getvar('recovery_opts.classifier') {
    out::message('# Backing up classification')
    run_task('peadm::backup_classification', $primary_target,
      directory => "${backup_directory}/classifier",
    )
  }

  if getvar('recovery_opts.ca') {
    out::message('# Backing up ca and ssl certificates')
    run_command(@("CMD"), $primary_target)
      /opt/puppetlabs/bin/puppet-backup create --dir=${shellquote($backup_directory)}/ca --scope=certs
      | CMD
  }

  # Check if /etc/puppetlabs/console-services/conf.d/secrets/keys.json exists and if so back it up
  if getvar('recovery_opts.rbac') {
    out::message('# Backing up ldap secret key if it exists')
    run_command(@("CMD"/L), $primary_target)
      test -f /etc/puppetlabs/console-services/conf.d/secrets/keys.json \
        && cp -rp /etc/puppetlabs/console-services/conf.d/secrets ${shellquote($backup_directory)}/rbac/ \
        || echo secret ldap key doesnt exist
      | CMD
  }

  # IF backing up orchestrator back up the secrets too /etc/puppetlabs/orchestration-services/conf.d/secrets/
  if getvar('recovery_opts.orchestrator') {
    out::message('# Backing up orchestrator secret keys')
    run_command(@("CMD"), $primary_target)
      cp -rp /etc/puppetlabs/orchestration-services/conf.d/secrets ${shellquote($backup_directory)}/orchestrator/
      | CMD
  }

  $backup_databases.each |$name,$database_target| {
    run_command(@("CMD"/L), $primary_target)
      /opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4 \
        -f ${shellquote($backup_directory)}/${shellquote($name)}/pe-${shellquote($name)}.dump.d \
        "sslmode=verify-ca \
         host=${shellquote($database_target.peadm::certname())} \
         user=pe-${shellquote($name)} \
         sslcert=/etc/puppetlabs/puppetdb/ssl/${shellquote($primary_target.peadm::certname())}.cert.pem \
         sslkey=/etc/puppetlabs/puppetdb/ssl/${shellquote($primary_target.peadm::certname())}.private_key.pem \
         sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem \
         dbname=pe-${shellquote($name)}"
      | CMD
  }

  run_command(@("CMD"/L), $primary_target)
    umask 0077 \
      && tar -czf ${shellquote($backup_directory)}.tar.gz ${shellquote($backup_directory)} \
      && rm -rf ${shellquote($backup_directory)}
    | CMD

  return({'path' => "${backup_directory}.tar.gz"})
}
