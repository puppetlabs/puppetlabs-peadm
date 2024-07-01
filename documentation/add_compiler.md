# Add Compiler

The `peadm::add_compiler` plan can be used to add a new compiler to a PE cluster or replace an existing one with new configuration.

## Add a compiler to an existing PE cluster

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

This command will retrieve the current PEADM configuration to determine the setup rules needed for a compiler's secondary PuppetDB instances. The plan will configure the primary with appropriate rules for allowing access from the new compiler. On the primary, the `puppet` service is stopped and the `pe-postgresql` service is reloaded. If required, a puppet agent is be installed. The compiler agent's certificate is be regenerated to include required data with `peadm::subplans::component_install`. Puppet agent will run on the following components
* _\<compiler-host\>_
* _\<primary_postgresql_host\>_
* _\<replica host\>_
* _\<primary_postgresql_host\>_

 The `puppet` service is then restarted.
