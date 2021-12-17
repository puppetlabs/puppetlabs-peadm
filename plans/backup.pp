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
  String                             $backup_directory       = '/tmp/'
){
  $database_to_backup = [ $backup_orchestrator, $backup_activity, $backup_rbac, $backup_puppetdb]
  $database_names     = [ 'pe-orchestrator' , 'pe-activity' , 'pe-rbac' , 'pe-puppetdb' ]

  # Convert inputs into targets.
  $primary_target                   = peadm::get_targets($primary_host, 1)
  $replica_target                   = peadm::get_targets($replica_host, 1)
  $replica_postgresql_target        = peadm::get_targets($replica_postgresql_host, 1)
  $compiler_targets                 = peadm::get_targets($compiler_hosts)
  $primary_postgresql_target        = peadm::get_targets($primary_postgresql_host, 1)

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
    run_command("/opt/puppetlabs/bin/puppet-backup create --dir=${backup_directory} --scope=certs", $primary_target)
  }

  $database_to_backup.each |Integer $index, Boolean $value | {
    if $value {
    out::message("# Backing up database ${database_names[$index]}")
    run_command("sudo -u pe-postgres /opt/puppetlabs/server/bin/pg_dump -Fc \"${database_names[$index]}\" -f \"${backup_directory}/${database_names[$index]}_$(date +%Y%m%d%S).bin\" || echo \"Failed to dump database ${database_names[$index]}\"" , $primary_target)
    }
  }

# $database_backup=pe-activity
# out::message("# Backing up database ${database_backup}")
# run_command("sudo -u pe-postgres /opt/puppetlabs/server/bin/pg_dump -Fc \"${database_backup}\" -f \"${backup_directory}/${database_backup}_$(date +%Y%m%d%S).bin\" || echo \"Failed to dump database ${database_backup}\"" , $primary_target)
}
