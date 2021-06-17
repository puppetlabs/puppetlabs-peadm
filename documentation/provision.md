# Provision Puppet Enterprise using the peadm module

The peadm module can be used to provision new Puppet Enterprise infrastructure. Supported architectures include Standard, Large, and Extra Large.

The peadm provisioning plan creates base reference implementation. Once a base stack is stood up, you may need to continue and perform additional configuration and adjustments to reach your target state, depending on your use case.

## Reference Architectures

When provisioning a new PE stack using peadm, there are several different host parameters which can be specified. At a minimum, you must always specify the primary parameter. Depending on which architecture you are deploying, other host parameters may be needed as well. The following is a list of the architectures peadm can provision and the required parameters.

* Standard
    - primary
* Standard with DR
    - primary
    - primary-replica
* Large
    - primary
    - compilers
* Large with DR
    - primary
    - primary-replica
    - compilers
* Extra Large
    - primary
    - pdb-database
    - compilers (optional)
* Extra Large with DR
    - primary
    - primary-replica
    - pdb-database
    - pdb-database-replica
    - compilers (optional)

Supplying a combination of host parameters which does not match one of the supported architectures above will result in an unsupported architecture error.

## Usage

### Bolt 3 usage
We will name the bolt project `large_ha_peadm` in this example but the project name can be anything.  

1. Install Bolt on a jumphost. This can be the primary, or any other system. (via package)
2. Run `mkdir large_ha_peadm && cd large_ha_peadm && bolt project init large_ha_peadm --modules puppetlabs-peadm`        
4. Create an inventory file with connection information. Example included below.
5. Create a parameters file. Example included below.
6. Run `bolt plan run peadm::provision --params @params.json ` after the inventory and params files are created. 
   
          
### Bolt 2 usage

1. Install Bolt on a jumphost. This can be the primary, or any other system.
2. Download or git clone the peadm module and put it somewhere on the jumphost. e.g. ~/modules/peadm.
3. Download or git clone the module dependencies, and put them somewhere on the jumphost. e.g. ~/modules/stdlib, ~/modules/node\_manager, etc.
4. Create an inventory file with connection information. Example included below.
5. Create a parameters file. Example included below.
6. Run the peadm::provision plan with the inputs created. Example:

        bolt plan run peadm::provision \
          --inventory inventory.yaml \
          --modulepath ~/modules \
          --params @params.json 


Example inventory.yaml Bolt inventory file:

```yaml
---
groups:
  - name: puppet-enterprise-nodes
    config:
      transport: ssh
      ssh:
        host-key-check: false
        user: centos
        run-as: root
    targets:
      - pe-xl-core-0.lab1.puppet.vm
      - pe-xl-core-1.lab1.puppet.vm
      - pe-xl-core-2.lab1.puppet.vm
      - pe-xl-core-3.lab1.puppet.vm
      - name: pe-xl-compiler-0.lab1.puppet.vm
        uri: 10.234.6.45
      - name: pe-xl-compiler-1.lab1.puppet.vm
        uri: 10.234.14.131
```

Example params.json Bolt parameters file (shown: Extra Large with DR):

```json
{
  "primary_host": "pe-xl-core-0.lab1.puppet.vm",
  "primary_postgresql_host": "pe-xl-core-1.lab1.puppet.vm",
  "replica_host": "pe-xl-core-2.lab1.puppet.vm",
  "replica_postgresql_host": "pe-xl-core-3.lab1.puppet.vm",
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

If you wish to prevent the bolt host from transferring the installer tarball to the targets you can place the installer tar files on the target hosts in the staging directory.   This can save time over slow networks, but is best to just perform the bolt task on the target node (puppetserver).  The tar file will need to exist in the staging directory for the following configuration:

* /tmp on the Bolt host
* /tmp on the primary
* /tmp on the primary PuppetDB PostgreSQL (if used)
* /tmp on the replica PuppetDB PostgreSQL (if used)
## Online usage

The peadm::provision plan can be configured to download installation content directly to hosts. To configure online installation, set the `download_mode` parameter of the `peadm::provision` plan to `direct`. The direct mode is often more efficient when PE hosts have a route to the internet.

## Hostnames and Certificate Names

The various host parameters given to the peadm::provision or peadm::action::install plans will be set as Puppet certificate names. You must use the names here that you want the servers to be identified as by Puppet.

While it is not required that target names match hostnames, it _is_ required that target names be resolvable.

In the event that Bolt will reach servers by IP address or external DNS name rather than internal DNS name or desired certname, a Bolt inventory file should be used to specify URIs for each name. For example:

```yaml
---
targets:
  - name: pe-xl-core-0.lab1.puppet.vm
    uri: 10.234.6.45
  - name: pe-xl-core-1.lab1.puppet.vm
    uri: 10.234.14.131
```

A parameters JSON file can then reference the target names, which will become the Puppet certificate names, and Bolt will still be able to reach the systems by using the IP addresses or other DNS name specified as the URIs in the inventory.yaml file.

```json
{
  "primary_host": "pe-xl-core-0.lab1.puppet.vm",
  "replica_host": "pe-xl-core-1.lab1.puppet.vm",

  "console_password": "puppetlabs",
  "dns_alt_names": [ "puppet", "puppet.lab1.puppet.vm" ],
  "compiler_pool_address": "puppet.lab1.puppet.vm",
  "version": "2019.2.2"
}
```

## Implementation Reference

Provisioning can be broken down into two actions: [install](../plans/action/install.pp), and [configure](../plans/action/configure.pp). Installation currently requires ssh access to the un-provisioned nodes, but configure can be performed using the Orchestrator transport if installation has already been completed.

Besides getting Puppet Enterprise installed, the key configuration supporting Large and Extra Large architectures is laid out in four classification groups. Links are provided below to a Markdown document that describes the groups, and also to the Puppet manifest that actually configures them:

* [classification.md](classification.md)
* [peadm::setup::node\_manager class](../manifests/setup/node_manager.pp)

The reference implementation uses trusted facts to put nodes in the right groups. Because the important puppet\_enterprise::\* class parameters and data are specified in the console, it should also be safe to have a pe.conf present on both the primary, and the primary replica nodes.

