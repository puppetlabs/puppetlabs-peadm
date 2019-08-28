# PE Large Architecture


## Overview

This module can also be used to deploy a Puppet Enterprise Large Architecture.
Such an deployment differs from an Extra Large Architecture in that it does
**not** include an external database.  PuppetDB is served from the master.

**NOTE:** Currently, the module does not deploy a Large Architecture with HA.
The currently supported deployment architecture is shown below.

![Large Architecture without HA](images/PE_Large_Architecture_no_HA.png)


## Instructions

The process for deploying a PE Large Architecture is very similar to the
[basic_usage](basic_usage.md) for deploying the XL Architecture.  These two
differ only in the parameters supplied to the bolt plans.  Specifically, the
`puppetdb_database_host`, `master_replica_host`, and
`puppetdb_database_replica_host` parameters need to be omitted in order to
deploy a PE Large Architecture.

Ensuring that the parameters above are omitted from the `params.json` file,
the [basic usage instructions](basic_usage.md#basic-usage-instructions) can be
used to run the `pe_xl` plan in order to install and configure the deployment.

Example nodes.yaml Bolt inventory file:

```yaml
---
groups:
  - name: pe_xl_nodes
    config:
      transport: ssh
      ssh:
        host-key-check: false
        user: centos
        run-as: root
        tty: true
    nodes:
      - pe-xl-core-0.lab1.puppet.vm
      - pe-xl-compiler-0.lab1.puppet.vm
      - pe-xl-compiler-1.lab1.puppet.vm
```

Example params.json Bolt parameters file:

```json
{
  "install": true,
  "configure": true,
  "upgrade": false,

  "master_host": "pe-xl-core-0.lab1.puppet.vm",
  "compiler_hosts": [
    "pe-xl-compiler-0.lab1.puppet.vm",
    "pe-xl-compiler-1.lab1.puppet.vm"
  ],

  "console_password": "puppetlabs",
  "dns_alt_names": [ "puppet", "puppet.lab1.puppet.vm" ],
  "compiler_pool_address": "puppet.lab1.puppet.vm",
  "version": "2018.1.4"
}
```
