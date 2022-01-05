# @summary Backup the core user settings for puppet infrastructure
#
# This plan can backup data as outlined at insert doc 
# 
plan peadm::backup (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  Optional[Peadm::SingleTargetSpec] $replica_host            = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts          = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Which data to backup
  Boolean                            $backup_orchestrator    = true,
  Boolean                            $backup_rbac            = true,
  Boolean                            $backup_activity        = true,
  Boolean                            $backup_ca_ssl          = true,
  Boolean                            $backup_puppetdb        = false,
  Boolean                            $backup_classification  = true,
  String                             $output_directory       = '/tmp',
){
  # Create an array of the names of databases and whether they have to be backed up to use in a lambda later
  $database_to_backup = [ $backup_orchestrator, $backup_activity, $backup_rbac, $backup_puppetdb]
  $database_names     = [ 'pe-orchestrator' , 'pe-activity' , 'pe-rbac' , 'pe-puppetdb' ]

  # Database backups should take place on the postgress server
  if $primary_postgresql_host {
    $database_backup_server = $primary_postgresql_host
  } else {
    $database_backup_server = $primary_host
  }

  peadm::assert_supported_bolt_version()

  # Ensure input valid for a supported architecture
  $arch = peadm::assert_supported_architecture(
    $primary_host,
    $replica_host,
    $primary_postgresql_host,
    $replica_postgresql_host,
    $compiler_hosts,
  )

  if $backup_classification {
    out::message('# Backing up classification')
    run_task('peadm::backup_classification', $primary_host,
    directory => $backup_directory,
    )
  }

  if $backup_ca_ssl {
    out::message('# Backing up ca and ssl certificates')
    run_command("/opt/puppetlabs/bin/puppet-backup create --dir=${backup_directory} --scope=certs", $primary_host)
  }

  $database_to_backup.each |Integer $index, Boolean $value | {
    if $value {
    out::message("# Backing up database ${database_names[$index]}")
    run_command("sudo -u pe-postgres /opt/puppetlabs/server/bin/pg_dump -Fc \"${database_names[$index]}\" -f \"${backup_directory}/${database_names[$index]}_$(date +%Y%m%d%S).bin\" || echo \"Failed to dump database ${database_names[$index]}\"" , $database_backup_server) # lint:ignore:140chars
    }
  }
}
