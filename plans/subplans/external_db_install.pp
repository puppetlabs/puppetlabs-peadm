# This plan is in development and currently considered experimental.
#
# @api private
#
# @summary Add a new PostgreSQL backend for PuppetDB to a PE architecture
# @param avail_group_letter _ Either A or B; whichever of the two letter designations the database is being assigned to
# @param dns_alt_names _ A comma_separated list of DNS alt names for the database
# @param database_host _ The hostname and certname of the new database
# @param primary_host _ The hostname and certname of the primary Puppet server
plan peadm::subplans::external_db_install(
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $primary_host,
  Optional[String[1]] $dns_alt_names = undef,
  Enum['A', 'B'] $avail_group_letter
){
  $database_target           = peadm::get_targets($targets, 1)
  $primary_target            = peadm::get_targets($primary_host, 1)

  run_plan('peadm::subplans::prepare_agent', $database_target,
    primary_host           => $primary_target,
    dns_alt_name           => $dns_alt_names,
    certificate_extensions => {
      peadm::oid('peadm_role')               => 'puppet/puppetdb-database',
      peadm::oid('peadm_availability_group') => $avail_group_letter,
    }
  )

  # On <compiler-host>, run the puppet agent
  run_task('peadm::puppet_runonce', $database_target)

  return("Adding or replacing database ${$database_target.peadm::certname()} succeeded.")

}
