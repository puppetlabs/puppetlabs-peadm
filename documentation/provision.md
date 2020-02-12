# Provision Puppet Enterprise using the peadm module

The peadm module can be used to provision new Puppet Enterprise infrastructure. Supported architectures include Standard, Large, and Extra Large.

The peadm provisioning plan creates base reference implementation. Once a base stack is stood up, you may need to continue and perform additional configuration and adjustments to reach your target state, depending on your use case.

## Reference Architectures

When provisioning a new PE stack using peadm, there are several different host parameters which can be specified. At a minimum, you must always specify the Puppet master. Depending on which architecture you are deploying, other host parameters may be needed as well. The following is a list of the architectures peadm can provision.

* Standard
    - master
* Standard with HA
    - master
    - master-replica
* Large
    - master
    - compilers
* Large with HA
    - master
    - master-replica
    - compilers
* Extra Large
    - master
    - pdb-database
    - compilers (optional)
* Extra Large with HA
    - master
    - master-replica
    - pdb-database
    - pdb-database-replica
    - compilers (optional)

Supplying a combination of host parameters which does not match one of the supported architectures above will result in an unsupported architecture error.

## Usage

1. Install Bolt on a jumphost. This can be the master, or any other system.
2. Download or git clone the peadm module and put it somewhere on the jumphost. e.g. ~/modules/peadm.
3. Download or git clone the module dependencies, and put them somewhere on the jumphost. e.g. ~/modules/stdlib, ~/modules/node\_manager, etc.
4. Ensure the hostname of each system is set correctly, to the same value that will be used to connect to the system, and refer to the system as. If the hostname is not set as expected the installation plan will refuse to continue.
5. Create an inventory file with connection information. Example included below.
6. Create a parameters file. Example included below.
7. Run the peadm::provision plan with the inputs created. Example:

        bolt plan run peadm::provision \
          --inventory inventory.yaml \
          --modulepath ~/modules \
          --params @params.json 

Example inventory.yaml Bolt inventory file:

```yaml
---
groups:
  - name: pe_nodes
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

Example params.json Bolt parameters file (shown: Extra Large with HA):

```json
{
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
  "version": "2019.1.1"
}
```

Review the [peadm::provision plan](../plans/provision.pp) to learn about more advanced provisioning options. It is possible to supply an ssh private key and git clone URL for a control-repo as part of provisioning, for example.

## Offline usage

The peadm::provision plan downloads installation content from an online repository by default. To perform an offline installation, you can prefetch the needed content and place it in the staging directory. If content is available in the staging directory, peadm::provision will not try to download it.

The default staging directory is `/tmp`. If a different staging dir is being used, it can be specified using the `stagingdir` parameter to the peadm::provision plan.

The content needed is the PE installation tarball for the target version. The installation content should be in the staging dir, and should have its original name. E.g. `/tmp/puppet-enterprise-2019.2.2-el-7-x86_64.tar.gz`.

Installation content can be downloaded from [https://puppet.com/try-puppet/puppet-enterprise/download/](https://puppet.com/try-puppet/puppet-enterprise/download/).

## Implementation Reference

Provisioning can be broken down into two actions: [install](../plans/action/install.pp), and [configure](../plans/action/configure.pp). Installation currently requires ssh access to the un-provisioned nodes, but configure can be performed using the Orchestrator transport if installation has already been completed.

Besides getting Puppet Enterprise installed, the key configuration supporting Large and Extra Large architectures is laid out in four classification groups. Links are provided below to a Markdown document that describes the groups, and also to the Puppet manifest that actually configures them:

* [classification.md](classification.md)
* [peadm::setup::node\_manager class](../manifests/setup/node_manager.pp)

The reference implementation uses trusted facts to put nodes in the right groups. Because the important puppet\_enterprise::\* class parameters and data are specified in the console, it should also be safe to have a pe.conf present on both the master, and the master replica nodes.

