# Old Versions of Puppet Enterprise (pe) Administration (adm) Module

Prior to the 1.0.0 release of peadm, the pp\_application and pp\_cluster trusted facts were used to identify peadm server roles and availability groups. In order to avoid conflict with customer use of these trusted facts, in 1.0.0 peadm switched to using its own custom OID trusted facts for the purpose instead.

Puppet Enterprise systems deployed with peadm 1.0.0 will use the correct trusted facts, but any system deployed with peadm 0.5.x or older will still be relying on pp\_application and pp\_cluster. It is recommended that for these systems, you either:

* Continue to use an older version of peadm to perform upgrades
* Deploy new PE infrastructure using a 1.0.0 version of peadm or newer
* Use the peadm::misc::upgrade\_trusted\_facts plan to re-issue certificates for each server to include the new custom OID trusted facts

Utilities are provided to perform a conversion, but expect them to be rough and require some tinkering if you choose this option.

## Convert an Existing Deployment

Prepare to run the plan against all servers in the PE infrastructure, using a params.json file such as this one:

```json
{
  "master_host": "pe-xl-core-0.lab1.puppet.vm",
  "targets": [
    "pe-xl-core-0.lab1.puppet.vm",
    "pe-xl-core-1.lab1.puppet.vm",
    "pe-xl-core-2.lab1.puppet.vm",
    "pe-xl-core-3.lab1.puppet.vm",
    "pe-xl-compiler-0.lab1.puppet.vm",
    "pe-xl-compiler-1.lab1.puppet.vm"
  ],
}
```

Run the plan. Note that this cannot be done using the Orchestrator transport; it must be performed over ssh.

```
bolt plan run peadm::misc::upgrade_trusted_facts --params @params.json 
```

To complete the conversion, the PE node groups in the console should be updated to use the new trusted fact OIDs, and not pp\_application or pp\_cluster anymore. This can be accomplished by re-applying the peadm::setup::node\_manager class to the master. Create a file such as the following called new-peadm.pp, replacing all server names listed with the correct ones for your deployment:

```puppet
file { 'node_manager.yaml':
  ensure  => file,
  noop    => false,
  mode    => '0644',
  path    => Deferred('peadm::node_manager_yaml_location'),
  content => epp('peadm/node_manager.yaml.epp', {
    server => 'pe-xl-core-0.lab1.puppet.vm',,
  }),
}

class { 'peadm::setup::node_manager':
  master_host                    => 'pe-xl-core-0.lab1.puppet.vm',
  master_replica_host            => 'pe-xl-core-2.lab1.puppet.vm',
  puppetdb_database_host         => 'pe-xl-core-1.lab1.puppet.vm',
  puppetdb_database_replica_host => 'pe-xl-core-3.lab1.puppet.vm',
  compiler_pool_address          => 'puppet.lab1.puppet.vm',
  require                        => File['node_manager.yaml'],
}
```

Finally, use Bolt to apply the configuration to the master.

Tip: use the `--noop` flag first to validate that the changes which will be made are the changes expected before applying the configuration change.

```
bolt apply --target pe-xl-core-0.lab1.puppet.vm new-peadm.pp
```
