#!/opt/puppetlabs/bin/puppet apply
function param($name) { inline_template("<%= ENV['PT_${name}'] %>") }

$puppetdb_database_replica_host=param('puppetdb_database_replica_host')

node_group { 'PE HA Replica':
  ensure   => 'present',
  classes  => {
    'puppet_enterprise::profile::primary_master_replica' => {
      'database_host_puppetdb' => $puppetdb_database_replica_host
    }
  },
}
