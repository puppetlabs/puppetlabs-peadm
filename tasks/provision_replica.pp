#!/opt/puppetlabs/bin/puppet apply --debug
function param($name) { inline_template("<%= ENV['PT_${name}'] %>") }

$default_environment = 'production'
$environments        = ['production']

# Configure HA
node_group { 'PE HA Master':
  ensure               => 'present',
  classes              => {
  'puppet_enterprise::profile::console' => {
    'replication_mode' => 'source'
  },
  'puppet_enterprise::profile::database' => {
    'replica_hostnames' => [param(primary_master_replica)],
    'replication_mode' => 'source'
  },
  'puppet_enterprise::profile::master' => {
    'file_sync_enabled' => true,
    'provisioned_replicas' => [param(primary_master_replica)],
    'replication_mode' => 'source'
  },
  'puppet_enterprise::profile::puppetdb' => {
    'sync_whitelist' => [param(primary_master_replica)]
    }
  },
  environment          => 'production',
  parent               => 'PE Master',
  rule                 => ['or',
  ['=', 'name', primary_master_host]],
}

node_group { 'PE HA Replica':
  ensure               => 'present',
  classes              => {
  'puppet_enterprise::profile::primary_master_replica' => {
    }
  },
  environment          => 'production',
  parent               => 'PE Infrastructure',
  rule                 => ['or',
  ['=', 'name', param(primary_master_replica)]],
}
