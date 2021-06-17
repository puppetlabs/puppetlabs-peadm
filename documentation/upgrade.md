# Upgrade Puppet Enterprise using the peadm module

Puppet Enterprise deployments provisioned using the peadm module can be upgrading using the peadm module as well.

## Usage

The `peadm::upgrade` plan requires as input the version of PE to upgrade to, and the names of each PE infrastructure host. Primary, replica, compilers, etc.

The following is an example parameters file for upgrading an Extra Large architecture deployment of PE 2019.0.1 to PE 2019.2.2.

```json
{
  "version": "2019.2.2",
  "primary_host": "pe-master-09a40c-0.us-west1-a.c.reidmv-peadm.internal",
  "primary_postgresql_host": "pe-psql-09a40c-0.us-west1-a.c.reidmv-peadm.internal",
  "replica_host": "pe-master-09a40c-1.us-west1-b.c.reidmv-peadm.internal",
  "replica_postgresql_host": "pe-psql-09a40c-1.us-west1-b.c.reidmv-peadm.internal",
  "compiler_hosts": [
    "pe-compiler-09a40c-0.us-west1-a.c.reidmv-peadm.internal",
    "pe-compiler-09a40c-1.us-west1-b.c.reidmv-peadm.internal",
    "pe-compiler-09a40c-2.us-west1-c.c.reidmv-peadm.internal",
    "pe-compiler-09a40c-3.us-west1-a.c.reidmv-peadm.internal"
  ]
}
```

The upgrade plan may be run as:

```
bolt plan run peadm::upgrade --params @params.json 
```

## Offline Usage

The peadm::upgrade plan downloads installation content from an online repository by default. To perform an offline installation, you can prefetch the needed content and place it in the staging directory. If content is available in the staging directory, peadm::upgrade will not try to download it.

The default staging directory is `/tmp`. If a different staging dir is being used, it can be specified using the `stagingdir` parameter to the peadm::upgrade plan.

The content needed is the PE installation tarball for the target version. The installation content should be in the staging dir, and should have its original name. E.g. `/tmp/puppet-enterprise-2019.2.2-el-7-x86_64.tar.gz`.

Installation content can be downloaded from [https://puppet.com/try-puppet/puppet-enterprise/download/](https://puppet.com/try-puppet/puppet-enterprise/download/).

## Online usage

The peadm::provision plan can be configured to download installation content directly to hosts. To configure online installation, set the `download_mode` parameter of the `peadm::provision` plan to `direct`. The direct mode is often more efficient when PE hosts have a route to the internet.

## Usage over the Orchestrator transport

The peadm::upgrade plan can be used with the Orchestrator (pcp) transport, provided that the Bolt executor is running as root on the primary. To use the Orchestrator transport prepare an inventory file such as the following to set the default transport to be `pcp`, but the replica specifically to be `local`.

```
---
version: 2
config:
  transport: pcp
  pcp:
    cacert: /etc/puppetlabs/puppet/ssl/certs/ca.pem
    service-url: https://pe-master-ad1d88-0.us-west1-a.c.reidmv-peadm.internal:8143
    task-environment: production
    token-file: /root/.puppetlabs/token
groups:
  - name: pe-targets
    targets:
      - name: "pe-master-ad1d88-0.us-west1-a.c.reidmv-peadm.internal"
        config:
          transport: local
      - name: "pe-master-ad1d88-1.us-west1-b.c.reidmv-peadm.internal"
      - name: "pe-compiler-ad1d88-0.us-west1-a.c.reidmv-peadm.internal"
      - name: "pe-compiler-ad1d88-1.us-west1-b.c.reidmv-peadm.internal"
      - name: "pe-compiler-ad1d88-2.us-west1-c.c.reidmv-peadm.internal"
      - name: "pe-compiler-ad1d88-3.us-west1-a.c.reidmv-peadm.internal"
      - name: "pe-psql-ad1d88-0.us-west1-a.c.reidmv-peadm.internal"
      - name: "pe-psql-ad1d88-1.us-west1-b.c.reidmv-peadm.internal"
```

Additionally, you MUST pre-stage a copy of the PE installation media in /tmp on the PuppetDB PostgreSQL node(s), if present. The Orchestrator transport cannot be used to send large files to remote systems, and the plan will fail if tries.

Pre-staging the installation media and using an inventory definition such as the example above, the peadm::upgrade plan can be run as normal. It will not rely on the Orchestrator service to operate on the primary, and it will use the Orchestrator transport to operate on other PE nodes.

```
bolt plan run peadm::upgrade --params @params.json 
```

## Retry or resume plan

This plan is broken down into steps. Normally, the plan runs through all the steps from start to finish. The name of each step is displayed during the plan run, as the step begins.

The `begin_at_step` parameter can be used to facilitate re-running this plan after a failed attempt, skipping past any steps that already completed successfully on the first try and picking up again at the step specified. The step name to resume at can be read from the previous run logs. A full list of available values for this parameter can be viewed by running `bolt plan show peadm::upgrade`.

## Manual Upgrades

In the event a manual upgrade is required, the steps may be followed along by reading directly from [the upgrade plan](../plans/upgrade.pp), which is itself the most accurate technical description of the steps required. In general form, the upgrade process is as given below.

Note: it is assumed that the Puppet primary is in cluster A when the upgrade starts, and that the replica is in cluster B. If the primary is in cluster B, the A/B designations in the instruction should be inverted.

**Phase 1: stop puppet service**

* Stop the `puppet` service on all PE infrastructure nodes to prevent normal automatic runs from interfering with the upgrade process

**Phase 2: upgrade DR cluster A**

1. Shut down the `pe-puppetdb` service on the compilers in cluster A
2. If different from the primary, run the `install-puppet-enterprise` script for the new PE version on the PuppetDB PostgreSQL node for cluster A
3. Run the `install-puppet-enterprise` script for the new PE version on the primary
4. Run `puppet agent -t` on the primary
5. If different from the primary, Run `puppet agent -t` on the PuppetDB PostgreSQL node for cluster A
6. Perform the compiler upgrade using `puppet infra upgrade compiler` for the compilers in cluster A

**Phase 3: upgrade DR cluster B**

1. Shut down the `pe-puppetdb` service on the compilers in cluster B
2. If different from the primary (replica), run the `install-puppet-enterprise` script for the new PE version on the PuppetDB PostgreSQL node for cluster B
3. If different from the primary (replica), Run `puppet agent -t` on the PuppetDB PostgreSQL node for cluster B
5. Run `puppet agent -t` on the primary to ensure orchestration services are configured and restarted before the next steps
6. Perform the replica upgrade using `puppet infra upgrade replica` for the primary (replica)
7. Perform the compiler upgrade using `puppet infra upgrade compiler` for the compilers in cluster B

**If Upgrading from 2019.5**

The following steps apply _only_ if upgrading from 2019.5 or older

1. Run `puppet infra run convert_legacy_compiler` for all compilers
2. Modify the peadm node groups "PE Compiler Group A" and "PE Compiler Group B" as follows:
    * Re-parent the groups. They should be children of "PE Compiler"
    * Remove configuration data (Hiera data). Leave the classes and class parameters
    * Add the rule `trusted.extensions.pp_auth_role = pe_compiler`
    * Remove the rule `trusted.extensions."1.3.6.1.4.1.34380.1.1.9812" = puppet/compiler`

**Phase 4: resume puppet service**

* Ensure the `puppet` service on all PE infrastructure nodes is running again

## Upgrade from 2018.1

To upgrade to PE 2019.7 or newer from PE 2018.1:

1. Run the peadm::convert plan
2. Run the peadm::upgrade plan
