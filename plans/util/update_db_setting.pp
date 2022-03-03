# @api private
#
# @summary Configure first-time classification and DR setup
#
# @param compiler_pool_address 
#   The service address used by agents to connect to compilers, or the Puppet
#   service. Typically this is a load balancer.
# @param internal_compiler_a_pool_address
#   A load balancer address directing traffic to any of the "A" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
# @param internal_compiler_b_pool_address
#   A load balancer address directing traffic to any of the "B" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
#
plan peadm::util::update_db_setting (
  TargetSpec                        $targets,
  Optional[Peadm::SingleTargetSpec] $new_postgresql_host     = undef,
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,
  Hash                              $peadm_config
) {
  # TODO: get and validate PE version

  # Convert inputs into targets.
  $primary_postgresql_target = peadm::get_targets($primary_postgresql_host, 1)
  $replica_postgresql_target = peadm::get_targets($replica_postgresql_host, 1)

  $roles = $peadm_config['role-letter']

  $targets.each |$target| {
    # Availability group does not matter for configuration order if adding a
    # database for the first time
    if ! $replica_postgresql_host {
      $write_setting = "//${primary_postgresql_host}:5432/pe-puppetdb?ssl=true&sslfactory=org.postgresql.ssl.jdbc4.LibPQFactory&sslmode=verify-full&sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem&sslkey=/etc/puppetlabs/puppetdb/ssl/${target.peadm::certname()}.private_key.pk8&sslcert=/etc/puppetlabs/puppetdb/ssl/${$target.peadm::certname()}.cert.pem"
      $read_setting = $write_setting
    }

    # Determine configuration order by pairing target with existing availability
    # letter assignments
    if ($primary_postgresql_host and $replica_postgresql_host) {
      $target_group_letter = peadm::flatten_compact([$roles['compilers'],$roles['server']].map |$role| {
        $role.map |$k,$v| {
          if $target.peadm::certname() in $v { $k }
        }
      })[0]
      $match = $roles['postgresql'][$target_group_letter]
      if $match {
        $first = $match
      } else {
        $first = $new_postgresql_host
      }

      $second = [$primary_postgresql_host, $replica_postgresql_host].reject($first)[0]

      $write_setting = "//${first}:5432/pe-puppetdb?ssl=true&sslfactory=org.postgresql.ssl.jdbc4.LibPQFactory&sslmode=verify-full&sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem&sslkey=/etc/puppetlabs/puppetdb/ssl/${target.peadm::certname()}.private_key.pk8&sslcert=/etc/puppetlabs/puppetdb/ssl/${$target.peadm::certname()}.cert.pem"
      $read_setting = "//${second}:5432/pe-puppetdb?ssl=true&sslfactory=org.postgresql.ssl.jdbc4.LibPQFactory&sslmode=verify-full&sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem&sslkey=/etc/puppetlabs/puppetdb/ssl/${target.peadm::certname()}.private_key.pk8&sslcert=/etc/puppetlabs/puppetdb/ssl/${$target.peadm::certname()}.cert.pem"
    }

    apply($target) {

      ini_setting { 'database_setting':
        ensure  => present,
        path    => '/etc/puppetlabs/puppetdb/conf.d/database.ini',
        section => 'database',
        setting => 'subname',
        value   => $write_setting,
      }

      ini_setting { 'read_database_setting':
        ensure  => present,
        path    => '/etc/puppetlabs/puppetdb/conf.d/read_database.ini',
        section => 'read-database',
        setting => 'subname',
        value   => $read_setting,
      }
    }
  }

  return('PuppetDB settings were updated for Puppet Enterprise compiler components successfully.')
}
