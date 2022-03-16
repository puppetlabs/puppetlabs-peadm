# @api private
#
# @summary Make updates to PuppetDB database settings
#
plan peadm::util::update_db_setting (
  TargetSpec                        $targets,
  Optional[Peadm::SingleTargetSpec] $new_postgresql_host     = undef,
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,
  Optional[Hash]                    $peadm_config            = undef,
) {

  # Convert inputs into targets.
  $primary_postgresql_target = peadm::get_targets($primary_postgresql_host, 1)
  $replica_postgresql_target = peadm::get_targets($replica_postgresql_host, 1)

  # Originally written to handle some additional logic which was eventually
  # determined to not be useful and was pulled out. As a result could use
  # more additional simplification. The goal is to match each infrastructure
  # component to the PostgreSQL nodes which corresponds to their availability
  # letter and if a match is not found, assume that new node is the match.
  #
  # FIX ME: Test removal of $primary_potsgresql_host and $replica_postgresql_host 
  # parameter check. Likely only parameter needed is the node be added. Section
  # also needs to be parallelized, can't use built functionality of apply().
  get_targets($targets).each |$target| {

    # Availability group does not matter if only one PSQL node in the cluster
    if ($primary_postgresql_host and $replica_postgresql_host) {

      # Existing config used to dynamically pair nodes with appropriate PSQL
      # server
      $roles = $peadm_config['role-letter']

      # Determine configuration by pairing target with existing availability letter
      # assignments, setting to the new node if no match is found.
      $target_group_letter = peadm::flatten_compact([$roles['compilers'],$roles['server']].map |$role| {
        $role.map |$k,$v| {
          if $target.peadm::certname() in $v { $k }
        }
      })[0]
      $match = $roles['postgresql'][$target_group_letter]
      if $match {
        $db = $match
      } else {
        $db = $new_postgresql_host
      }

      $db_setting = "//${db}:5432/pe-puppetdb?ssl=true&sslfactory=org.postgresql.ssl.jdbc4.LibPQFactory&sslmode=verify-full&sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem&sslkey=/etc/puppetlabs/puppetdb/ssl/${target.peadm::certname()}.private_key.pk8&sslcert=/etc/puppetlabs/puppetdb/ssl/${$target.peadm::certname()}.cert.pem"
    } else {
      $db_setting = "//${primary_postgresql_host}:5432/pe-puppetdb?ssl=true&sslfactory=org.postgresql.ssl.jdbc4.LibPQFactory&sslmode=verify-full&sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem&sslkey=/etc/puppetlabs/puppetdb/ssl/${target.peadm::certname()}.private_key.pk8&sslcert=/etc/puppetlabs/puppetdb/ssl/${$target.peadm::certname()}.cert.pem"
    }

    # Introduced new dependency for PEADM to enable modification of INI files
    apply($target) {
      ini_setting { 'database_setting':
        ensure  => present,
        path    => '/etc/puppetlabs/puppetdb/conf.d/database.ini',
        section => 'database',
        setting => 'subname',
        value   => $db_setting,
      }

      ini_setting { 'read_database_setting':
        ensure  => present,
        path    => '/etc/puppetlabs/puppetdb/conf.d/read_database.ini',
        section => 'read-database',
        setting => 'subname',
        value   => $db_setting,
      }
    }
  }

  return('PuppetDB database settings were updated successfully.')
}
