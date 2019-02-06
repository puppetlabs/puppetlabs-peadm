# Basic usage

This is a base reference implementation. Once a base stack is stood up, you may need to continue and perform additional configuration and adjustments to reach your target state, depending on your use case.

The reference implementation currently includes Task Plans to install, configure, and later upgrade a new Extra Large HA stack.

The current versions of those plans can be found at:

* [install.pp](https://github.com/reidmv/reidmv-pe_xl/blob/master/plans/install.pp)
* [configure.pp](https://github.com/reidmv/reidmv-pe_xl/blob/master/plans/configure.pp)
* [upgrade.pp](https://github.com/reidmv/reidmv-pe_xl/blob/master/plans/upgrade.pp)

These are still a work in progress and lack documentation. Reading through them can give you an idea of what steps we've found to be required to deploy and configure all of the Puppet Enterprise components.

Besides getting everything installed the key configuration that makes this work is laid out in four classification groups. Links provided below to a Markdown document that describes the groups, and also to the Puppet manifest that actually configures them:

* [classification.md](https://github.com/reidmv/reidmv-pe_xl/blob/master/docs/classification.md)
* [pe\_xl::node\_manager class](https://github.com/reidmv/reidmv-pe_xl/blob/master/manifests/node_manager.pp)

The reference implementation uses trusted facts to put nodes in the right groups. Because the important puppet\_enterprise::\* class parameters and data are specified in the console, it should also be safe to have a pe.conf present on both the master, and the master replica nodes.

## Basic usage instructions

1. Ensure the hostname of each system is set correctly, to the same value that will be used to connect to the system, and refer to the system as. If the hostname is not set as expected the installation plan will refuse to continue.
2. Install Bolt on a jumphost. This can be the master, or any other system.
3. Download or git clone the pe\_xl module and put it somewhere on the jumphost, e.g. ~/modules/pe\_xl.
4. Create an inventory file with connection information. Example included below. Available Bolt configuration options are documented here.
5. Create a parameters file. Example included below. Note at the top of the file are arguments which dictate which plans should be run, such as install+configure.
6. Run the pe\_xl plan with the inputs created. Example:

        bolt plan run pe_xl \
          --inventory nodes.yaml \
          --modulepath ~/modules \
          --params @params.json 

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
      - pe-xl-core-1.lab1.puppet.vm
      - pe-xl-core-2.lab1.puppet.vm
      - pe-xl-core-3.lab1.puppet.vm
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
  "puppetdb_database_host": "pe-xl-core-1.lab1.puppet.vm",
  "master_replica_host": "pe-xl-core-2.lab1.puppet.vm",
  "puppetdb_database_replica_host": "pe-xl-core-3.lab1.puppet.vm",
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
