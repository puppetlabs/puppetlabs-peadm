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

The pe\_xl::upgrade plan downloads installation content from an online repository by default. To perform an offline installation, you can prefetch the needed content and place it in the staging directory. If content is available in the staging directory, pe\_xl::upgrade will not try to download it.

The default staging directory is `/tmp`. If a different staging dir is being used, it can be specified using the `stagingdir` parameter to the pe\_xl::upgrade plan.

The content needed is the PE installation tarball for the target version. The installation content should be in the staging dir, and should have its original name. E.g. `/tmp/puppet-enterprise-2019.2.2-el-7-x86_64.tar.gz`.

Installation content can be downloaded from [https://puppet.com/try-puppet/puppet-enterprise/download/](https://puppet.com/try-puppet/puppet-enterprise/download/).

## Usage over the Orchestrator transport

The pe\_xl::upgrade plan can be used with the Orchestrator (pcp) transport, provided that the Bolt executor is running as root on the master. To use the Orchestrator transport prepare an inventory file such as the following to set the default transport to be `pcp`, but the master specifically to be `local`.

```
---
version: 2
config:
  transport: pcp
  pcp:
    cacert: /etc/puppetlabs/puppet/ssl/certs/ca.pem
    service-url: https://pe-master-ad1d88-0.us-west1-a.c.reidmv-pe_xl.internal:8143
    task-environment: production
    token-file: /root/.puppetlabs/token
groups:
  - name: pe-targets
    targets:
      - name: "pe-master-ad1d88-0.us-west1-a.c.reidmv-pe_xl.internal"
        config:
          transport: local
      - name: "pe-master-ad1d88-1.us-west1-b.c.reidmv-pe_xl.internal"
      - name: "pe-compiler-ad1d88-0.us-west1-a.c.reidmv-pe_xl.internal"
      - name: "pe-compiler-ad1d88-1.us-west1-b.c.reidmv-pe_xl.internal"
      - name: "pe-compiler-ad1d88-2.us-west1-c.c.reidmv-pe_xl.internal"
      - name: "pe-compiler-ad1d88-3.us-west1-a.c.reidmv-pe_xl.internal"
      - name: "pe-psql-ad1d88-0.us-west1-a.c.reidmv-pe_xl.internal"
      - name: "pe-psql-ad1d88-1.us-west1-b.c.reidmv-pe_xl.internal"
```

Additionally, you MUST pre-stage a copy of the PE installation media in /tmp on the PuppetDB PostgreSQL node(s), if present. The Orchestrator transport cannot be used to send large files to remote systems, and the plan will fail if tries.

Pre-staging the installation media and using an inventory definition such as the example above, the pe\_xl::upgrade plan can be run as normal. It will not rely on the Orchestrator service to operate on the master, and it will use the Orchestrator transport to operate on other PE nodes.

```
bolt plan run pe_xl::upgrade --params @params.json 
```

## Manual Upgrades

In the event a manual upgrade is required, the steps may be followed along by reading directly from [the upgrade plan](../plans/upgrade.pp), which is itself the most accurate technical description of the steps required. In general form, the upgrade process is as given below.

Note: it is assumed that the Puppet master is in cluster A when the upgrade starts, and that the replica is in cluster B. If the master is in cluster B, the A/B designations in the instruction should be inverted.

**Phase 1: stop puppet service**

* Stop the `puppet` service on all PE infrastructure nodes to prevent normal automatic runs from interfering with the upgrade process

**Phase 2: upgrade HA cluster A**

1. Shut down the `pe-puppetdb` service on the compilers in cluster A
2. If different from the master, run the `install-puppet-enterprise` script for the new PE version on the PuppetDB PostgreSQL node for cluster A
3. Run the `install-puppet-enterprise` script for the new PE version on the master
4. If different from the master, Run `puppet agent -t` on the PuppetDB PostgreSQL node for cluster A
5. Perform the standard `curl upgrade.sh | bash` procedure on the compilers for cluster A

**Phase 3: upgrade HA cluster B**

1. Shut down the `pe-puppetdb` service on the compilers in cluster B
2. If different from the master (replica), run the `install-puppet-enterprise` script for the new PE version on the PuppetDB PostgreSQL node for cluster B
3. If different from the master (replica), Run `puppet agent -t` on the PuppetDB PostgreSQL node for cluster B
4. Perform the standard `curl upgrade.sh | bash` procedure on the master (replica)
5. Perform the standard `curl upgrade.sh | bash` procedure on the compilers for cluster B

**Phase 4: resume puppet service**

* Ensure the `puppet` service on all PE infrastructure nodes is running again
