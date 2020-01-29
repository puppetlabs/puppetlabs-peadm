# Upgrade Puppet Enterprise using the pe\_xl module

Puppet Enterprise deployments provisioned using the pe\_xl module can be upgrading using the pe\_xl module as well.

## Usage

The `pe_xl::upgrade` plan requires as input the version of PE to upgrade to, and the names of each PE infrastructure host. Master, replica, compilers, etc.

The following is an example parameters file for upgrading an Extra Large architecture deployment of PE 2018.1.9 to PE 2018.1.11.

```json
{
  "version": "2018.1.11",
  "master_host": "pe-master-09a40c-0.us-west1-a.c.reidmv-pe_xl.internal",
  "puppetdb_database_host": "pe-psql-09a40c-0.us-west1-a.c.reidmv-pe_xl.internal",
  "master_replica_host": "pe-master-09a40c-1.us-west1-b.c.reidmv-pe_xl.internal",
  "puppetdb_database_replica_host": "pe-psql-09a40c-1.us-west1-b.c.reidmv-pe_xl.internal",
  "compiler_hosts": [
    "pe-compiler-09a40c-0.us-west1-a.c.reidmv-pe_xl.internal",
    "pe-compiler-09a40c-1.us-west1-b.c.reidmv-pe_xl.internal",
    "pe-compiler-09a40c-2.us-west1-c.c.reidmv-pe_xl.internal",
    "pe-compiler-09a40c-3.us-west1-a.c.reidmv-pe_xl.internal"
  ]
}
```

The upgrade plan may be run as:

```
bolt plan run pe_xl::upgrade --params @params.json 
```

## Offline Usage

The pe\xl::upgrade plan downloads installation content from an online repository by default. To perform an offline installation, you can prefetch the needed content and place it in the staging directory. If content is available in the staging directory, pe\_xl::upgrade will not try to download it.

The default staging directory is `/tmp`. If a different staging dir is being used, it can be specified using the `stagingdir` parameter to the pe\_xl::upgrade plan.

The content needed is the PE installation tarball for the target version. The installation content should be in the staging dir, and should have its original name. E.g. `/tmp/puppet-enterprise-2019.2.2-el-7-x86_64.tar.gz`.

Installation content can be downloaded from [https://puppet.com/try-puppet/puppet-enterprise/download/](https://puppet.com/try-puppet/puppet-enterprise/download/).

## Manual Upgrades

In the event a manual upgrade is required, the steps may be followed along by reading directly from [the upgrade plan](../plans/upgrade.pp), which is itself the most accurate technical description of the steps required. In general form, the upgrade process is as given below.

Note: it is assumed that the Puppet master is in cluster A when the upgrade starts, and that the replica is in cluster B. If the master is in cluster B, the A/B designations in the instruction should be inverted.

**Phase 1: stop puppet service**

* Stop the `puppet` service on all PE infrastructure nodes to prevent normal automatic runs from interfering with the upgrade process

**Phase 2: upgrade HA cluster A**

1. Shut down the `pe-puppetdb` service on the master and compilers in cluster A
2. If different from the master, run the `install-puppet-enterprise` script for the new PE version on the PuppetDB PostgreSQL node for cluster A
3. Run the `install-puppet-enterprise` script for the new PE version on the master
4. If different from the master, Run `puppet agent -t` on the PuppetDB PostgreSQL node for cluster A
5. Perform the standard `curl upgrade.sh | bash` procedure on the compilers for cluster A

**Phase 3: upgrade HA cluster B**

1. Shut down the `pe-puppetdb` service on the master (replica) and compilers in cluster B
2. If different from the master (replica), run the `install-puppet-enterprise` script for the new PE version on the PuppetDB PostgreSQL node for cluster B
3. If different from the master (replica), Run `puppet agent -t` on the PuppetDB PostgreSQL node for cluster B
4. Perform the standard `curl upgrade.sh | bash` procedure on the master (replica)
5. Perform the standard `curl upgrade.sh | bash` procedure on the compilers for cluster B

**Phase 4: resume puppet service**

* Ensure the `puppet` service on all PE infrastructure nodes is running again
