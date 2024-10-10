# Add Compilers

- [Add Compilers](#Add-Compilers)
  - [Introduction](#Introduction)
  - [Add compilers to an existing PE cluster](#Add-compilers-to-an-existing-PE-cluster)
  - [Running the `add_compilers` plan](#running-the-add_compilers-plan)
  - [Optional Parameters](#optional-parameters)

## Introduction

The `peadm::add_compilers` plan can be used to add new compilers to a PE cluster or replace an existing with new configuration.

## Add compilers to an existing PE cluster

As seen in the example below, this is the minimal parameters required to add a compiler to an existing PE cluster. These can be passed as command line variables to the plan, or in this case added to a params.json file.

```json
{
  "compiler_hosts": "pe-xl-compiler-0.lab1.puppet.vm",
  "primary_host": "pe-xl-core-0.lab1.puppet.vm"
}
```

And for multiple compilers, this is the minimal parameters required.

```json
{
  "compiler_hosts": [
    "pe-xl-compiler-0.lab1.puppet.vm",
    "pe-xl-compiler-1.lab1.puppet.vm"
  ],
  "primary_host": "pe-xl-core-0.lab1.puppet.vm"
}
```

## Running the `add_compiler` plan

```
bolt plan run peadm::add_compilers --params @params.json
```

This command will retrieve the current PEADM configuration to determine the setup rules needed for a compiler's secondary PuppetDB instances. The plan will configure the primary with appropriate rules for allowing access from the new compiler. On the primary, the `puppet` service is stopped and the `pe-postgresql` service is reloaded. If required, a puppet agent will be installed on the new compiler host. The compiler agent's certificate is regenerated to include data required by the `peadm::subplans::component_install` plan. A subsequent Puppet agent run will happen on the following components.

- _\<compiler-host\>_
- _\<primary_postgresql_host\>_
- _\<replica host\>_
- _\<primary_postgresql_host\>_

The `puppet` service is then restarted.

## Optional Parameters

As well as `compiler_hosts` and `primary_host`, the `add_compiler` plan has a number of optional parameters. These can be viewed in the following params example.

```json
{
  "avail_group_letter": "B",
  "compiler_hosts": "pe-xl-compiler-0.lab1.puppet.vm",
  "dns_alt_names": ["puppet,puppet.lab1.puppet.vm"],
  "primary_host": "pe-xl-core-0.lab1.puppet.vm",
  "primary_postgresql_host": "pe-psql-6251cd-0.us-west1-a.c.slice-cody.internal"
}
```

for multiple compilers.

```json
{
  "avail_group_letter": "B",
  "compiler_hosts": [
    "pe-xl-compiler-0.lab1.puppet.vm",
    "pe-xl-compiler-1.lab1.puppet.vm"
  ],
  "dns_alt_names": [
    "puppet,puppet.lab1.puppet.vm",
    "puppet2,puppet.lab2.puppet.vm"
  ],
  "primary_host": "pe-xl-core-0.lab1.puppet.vm",
  "primary_postgresql_host": "pe-psql-6251cd-0.us-west1-a.c.slice-cody.internal"
}
```

Please note, the optional parameters and values of the plan are as follows.

<!-- table -->

| Parameter                 | Default value | Description                                                                                                                    |
| ------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `avail_group_letter`      | `A`           | By default, each compiler will be added to the primary group A.                                                                |
| `dns_alt_names`           | `undef`       |                                                                                                                                |
| `primary_postgresql_host` | `undef`       | By default, this will pre-populate to the required value depending if your architecture contains HA and or external databases. |

For more information around adding compilers to your infrastructure [Expanding Your Deployment](expanding.md#adding-compilers-with-peadmadd_compiler)
