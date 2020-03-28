# Convert infrastructure for use with the peadm module

The peadm::convert plan can be used to adopt manually deployed infrastructure for use with peadm, or to adopt infrastructure deployed with a version of peadm older than 1.0.0.

## Convert an Existing Deployment

Prepare to run the plan against all servers in the PE infrastructure, using a params.json file such as this one:

```json
{
  "master_host": "pe-xl-core-0.lab1.puppet.vm",
  "master_replica_host": "pe-xl-core-1.lab1.puppet.vm",
  "compiler_hosts": [
    "pe-xl-compiler-0.lab1.puppet.vm",
    "pe-xl-compiler-1.lab1.puppet.vm"
  ],

  "compiler_pool_address": "puppet.lab1.puppet.vm",
}
```

See the [provision](provision.md#reference-architectures) documentation for a list of supported architectures. Note that for convert, *all infrastructure being converted must already be functional*; you cannot use convert to add new systems to the infrastructure, nor can you use it to change your architecture.

```
bolt plan run peadm::convert --params @params.json 
```
