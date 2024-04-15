# Add Compiler

The peadm::add_compiler plan can be used to add a new compiler to a PE architecture or replace an existing one with new configuration.

## Add compiler to an exising PE instance

Prepare to run the plan using a params.json file such as this one:

```json
{
  "avail_group_letter": "A",
  "compiler_host": "pe-xl-compiler-0.lab1.puppet.vm",
  "dns_alt_names": [ "puppet", "puppet.lab1.puppet.vm" ],
  "primary_host":  "pe-xl-core-0.lab1.puppet.vm",
  "primary_postgresql_host": "pe-psql-6251cd-0.us-west1-a.c.slice-cody.internal",
}
```

See the [install](install.md#reference-architectures) documentation for a list of supported architectures.


## Running the add_compiler plan
```
bolt plan run peadm::add_compiler --params @params.json 
```

This call will retreive the current peadm config to determain the setup rules needed for a compiler's secondary PuppetDB instances. The provided server will be configured with the appropriate rules for Puppet Server access from compiler. The puppet.service will be stopped and the pe-postgresql.service will be reloaded. If required and agent will be installed and regenerated agent certificate to add required data with peadm::subplans::component_install. Puppet agent will run on the following components
* _\<compiler-host\>_
* _\<primary_postgresql_host\>_
* _\<replica postgres host\>_
* _\<primary_postgresql_host\>_

 The `puppet` service is then restarted.
