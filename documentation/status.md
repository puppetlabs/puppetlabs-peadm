# Status Plan
The peadm module contains a plan that aggregates PE status output from one or more stacks into either a table view on the CLI, or JSON output to be consumed by a downstream report. 

This data can be extremely helpful if you run multiple stacks either in production or just want 
a simple status of your DEV, QA, and PROD PE stacks.  

## Table output
By default the status command assumes you will be running this plan on the CLI.  By running on the CLI the status plan will send a summarized table output to the console for you to review.
This is a heads up output of the status across all your stacks weither you have multiple environments or spread the load across different regions.  This plan will curate all the data into a single pane.

```shell
bolt plan run peadm::status -t pe_stacks verbose=true
Starting: plan peadm::status
Starting: task peadm::infrastatus on pnw_stack, east_stack, west_stack, northeast_stack
Finished: task peadm::infrastatus with 0 failures in 10.29 sec
+---------------------------------------+--------------------------------------+
|                         Overall Status: operational                          |
+---------------------------------------+--------------------------------------+
| Stack                                 | Status                               |
+---------------------------------------+--------------------------------------+
| pnw_stack                             | operational                          |
| east_stack                            | operational                          |
| west_stack                            | operational                          |
| northeast_stack                       | operational                          |
+---------------------------------------+--------------------------------------+
+-----------+---------------------------+--------------------------+-------------+
|                           Operational Service Status                           |
+-----------+---------------------------+--------------------------+-------------+
| Stack     | Service                   | Url                      | Status      |
+-----------+---------------------------+--------------------------+-------------+
| pnw_stack | code-manager-service      | pe-std.puppet.vm         | operational |
| pnw_stack | file-sync-storage-service | pe-std.puppet.vm         | operational |
| pnw_stack | file-sync-client-service  | pe-std-replica.puppet.vm | operational |
| pnw_stack | pe-master                 | pe-std-replica.puppet.vm | operational |
| pnw_stack | classifier-service        | pe-std-replica.puppet.vm | operational |
| pnw_stack | rbac-service              | pe-std-replica.puppet.vm | operational |
| pnw_stack | activity-service          | pe-std-replica.puppet.vm | operational |
| pnw_stack | orchestrator-service      | pe-std.puppet.vm         | operational |
| pnw_stack | broker-service            | pe-std.puppet.vm         | operational |
| pnw_stack | puppetdb-status           | pe-std-replica.puppet.vm | operational |
+-----------+---------------------------+--------------------------+-------------+
Finished: plan peadm::status in 10.59 sec
Plan completed successfully with no result
```

### Plan Usage
To use this plan run: `bolt plan run peadm::status -t pe_stacks --user=root`  

You are responsible for supplying the password securely via --password, --password-prompt, config file or some other way.  

There are a few parameters you can supply to the plan that alter the output of the plan.

1. format (table or json, defaults to table)
2. summarize(boolean, defaults to true, applicable to json output only)
3. colors (render colors in output, off by default for json)
4. verbose (shows the operationally services too instead of just the failing)

Example Invocations:

* `bolt plan run peadm::status -t pe_stacks format=json verbose=true`
* `bolt plan run peadm::status -t pe_stacks format=json verbose=true colors=true summarize=false`
* `bolt plan run peadm::status -t pe_stacks format=table verbose=true`

For a sample of the json output you can reference the following files:

* [summarized json plan output](./res/summarized.json)
* [raw json output from plan (slightly summarized)](./res/raw_summary.json)


**NOTE** This plan requires root privileges to run as it will call the bolt task infrastatus which then calls `/opt/puppetlabs/bin/puppet infra status`.  Should you need to add this command to your sudoers file or equilivent please use `/opt/puppetlabs/bin/puppet infra status`.  You may need to also add `/opt/puppetlabs/server/apps/enterprise/puppet-infra` but this file is a special file that puppet references internally to generate the `puppet infra` command.

### Task Usage
If you wish to run the bolt task `infrastatus` you can use: 

* `bolt task run peadm::infrastatus -t pe_stacks --user=root`
* `bolt task run peadm::infrastatus -t pe_stacks --user=root format=json` (For JSON output) 

 You are responsible for supplying the password securely via --password, --password-prompt, config file or some other way.   


**NOTE** This task requires root privileges to run.  Should you need to add this command to your sudoers file or equilivent please use `/opt/puppetlabs/bin/puppet infra status`.  You may need to also add `/opt/puppetlabs/server/apps/enterprise/puppet-infra` but this file is a special file that puppet references internally to generate the `puppet infra` command.

```shell
Finished on pnw_stack:
  Notice: Contacting services for status information...
  Code Manager: Running on Primary Master, https://pe-std.puppet.vm:8170/
  File Sync Storage Service: Running on Primary Master, https://pe-std.puppet.vm:8140/
  File Sync Client Service: Running on Primary Master, https://pe-std.puppet.vm:8140/
  Puppet Server: Running on Primary Master, https://pe-std.puppet.vm:8140/
  Classifier: Running on Primary Master, https://pe-std.puppet.vm:4433/classifier-api
  RBAC: Running on Primary Master, https://pe-std.puppet.vm:4433/rbac-api
  Activity Service: Running on Primary Master, https://pe-std.puppet.vm:4433/activity-api
  Orchestrator: Running on Primary Master, https://pe-std.puppet.vm:8143/orchestrator
  PCP Broker: Running on Primary Master, wss://pe-std.puppet.vm:8142/pcp
  PCP Broker v2: Running on Primary Master, wss://pe-std.puppet.vm:8142/pcp2
  PuppetDB: Running on Primary Master, https://pe-std.puppet.vm:8081/pdb
      Info: Last sync successfully completed 56 seconds ago (at 2020-04-07T22:15:48.649Z)
  File Sync Client Service: Running on Primary Master Replica, https://pe-std-replica.puppet.vm:8140/
  Puppet Server: Running on Primary Master Replica, https://pe-std-replica.puppet.vm:8140/
  Classifier: Running on Primary Master Replica, https://pe-std-replica.puppet.vm:4433/classifier-api
  RBAC: Running on Primary Master Replica, https://pe-std-replica.puppet.vm:4433/rbac-api
  Activity Service: Running on Primary Master Replica, https://pe-std-replica.puppet.vm:4433/activity-api
  PuppetDB: Running on Primary Master Replica, https://pe-std-replica.puppet.vm:8081/pdb
      Info: Last sync successfully completed 25 seconds ago (at 2020-04-07T22:16:20.231Z)
  2020-04-07 22:16:45 +0000
  17 of 17 services are fully operational.
  
```

## Inventory file setup
When using the status plan or task with bolt on the command line it is recommended to have a inventory file similar to the following.  Although your inventory will likely be different
and could have multiple groups.  The purpose of this setup is to get the status of the entire group
of systems and contain memorable names associated with the group and targets defined within.  You might also have groups for QA, DEV, TEST, PROD.  Some experimention may be required to get the configurations just right.  Additionally, you can always specify multiple groups with the bolt `-t` option.

In this example I have four reginal PE stacks which serve as my production PE stacks.  Each target within the group is the primary puppetserver and the port is the ssh port.  You could also use the pcp transport instead of ssh too.

```
---
version: 2
groups:
  - name: pe_stacks
    targets:
      - uri: ssh://192.168.0.9:22
        name: pnw_stack
      - uri: ssh://192.168.4.10:22
        name: east_stack
      - uri: ssh://192.168.8.11:22
        name: west_stack
      - uri: ssh://192.168.12.12:22
        name: northeast_stack
```        

For pcp transport please reference the [following pcp options](https://puppet.com/docs/bolt/latest/bolt_configuration_reference.html#pcp).  For ssh transport options please reference [ssh docs](https://puppet.com/docs/bolt/latest/bolt_configuration_reference.html#ssh)

If you wish to have a ssh and pcp transports configured you could use something similar to:

```
groups:
  config:
    pcp:
      service-url: pe-puppetmaster.example.com
      token-file: ~/.puppetlabs/secrets/token.yaml
    ssh:
      port: 22
      user: root
  - name: pe_stacks
    targets:
      - uri: 192.168.0.9
        name: pnw_stack
      - uri: 192.168.4.10
        name: east_stack
      - uri: 192.168.8.11
        name: west_stack
      - uri: 192.168.12.12
        name: northeast_stack
      
```

Then choose which transport to use at runtime:

`bolt plan run peadm::status -t pe_stacks --transport pcp` # ssh is the default transport


### Other notes
* At this time it is unknown what kind of performance hit on the PE systems the `puppet infra status` command demands.  Please measure and use cautiously.

