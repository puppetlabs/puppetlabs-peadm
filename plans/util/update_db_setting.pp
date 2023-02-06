# @api private
#
# @summary Make updates to PuppetDB database settings
#
plan peadm::util::update_db_setting (
  TargetSpec                        $targets,
  Optional[Peadm::SingleTargetSpec] $postgresql_host = undef,
  Optional[Hash]                    $peadm_config    = undef,
  Boolean                           $override        = false
) {
  # FIX ME: Section needs to be parallelized, can't use built in functionality
  # of apply().
  get_targets($targets).each |$target| {
    if $override {
      $db = $postgresql_host
    } else {
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
        $db = $postgresql_host
      }
    }

    $db_setting = "//${db}:5432/pe-puppetdb?ssl=true&sslfactory=org.postgresql.ssl.jdbc4.LibPQFactory&sslmode=verify-full&sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem&sslkey=/etc/puppetlabs/puppetdb/ssl/${target.peadm::certname()}.private_key.pk8&sslcert=/etc/puppetlabs/puppetdb/ssl/${$target.peadm::certname()}.cert.pem" # lint:ignore:140chars

    # Introduces dependency so PEADM can modify INI files
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
