# Add Replica

- [Add Replica](#Add-replica)
  - [Introduction](#Introduction)
  - [Adding Replica to Standard or Large infrastructure](#Adding-Replica-to-Standard-or-Large-infrastructure)
  - [Adding Replica to Extra Large infrastructure](#Adding-Replica-to-Extra-Large-infrastructure)
  - [Running the `add_replica` plan](#running-the-add_replica-plan)
  - [Parameters](#parameters)

## Introduction

The `peadm::add_replica` plan is designed to setup disaster recovery of a Primary Puppet Enterprise server. This is acheived through adding a primary replica to your system. Although this plan doesn't change your PE architcture, adding DR does depend on the structure of your current architecture.

In the case of Standard and Large installations, DR can be acheiveived by simply utilising this plan and adding the primary replica. In the case of an Extra Large infrastructure which includes an external DB, a replica DB is also required. This can be done with the `peadm::add_database` plan. For more detail see [Adding External Databases with peadm::add_database](expanding.md#adding-external-databases-with-peadmadd_database).

Please note, to setup a replica you must have code manager configured. To learn more about code manager, please see [Puppet Docs](help.puppet.com).

...

## Adding Replica to Standard or Large infrastructure
As seen below, this is an example of the required paramaters to add a primary replica. These paramaters can be passed in-line or as a params file.

```json
{
  "primary_host":  "pe-core-0.lab1.puppet.vm",
  "replica_host": "pe-replica-0.lab1.puppet.vm"
}
```

## Adding Replica to Extra Large infrastructure
In the below example, we have already have an external DB and a replica of it. This means that we should pass in the additional parameter of the replicas hostname.

```json
{
  "primary_host":  "pe-xl-core-0.lab1.puppet.vm",
  "compiler_host": "pe-xl-replica-0.lab1.puppet.vm",
  "replica_postgresql_host": "pe-xl-postgresql-replica-0.lab1.puppet.vm"
}
```

## Running the `add_replica` plan

```
bolt plan run peadm::add_replica --params @params.json 
```

The plan performs the following steps:

1. Installs Puppet Agent on the new replica host.
2. Updates classifications with new replica configuration.
3. Provisons the infrastructre replica with PE.

## Parameters

### `primary_host`

- **Type:** `Peadm::SingleTargetSpec`
- **Description:**  
  The hostname and certname of the primary Puppet server .

### `replica_host`

- **Type:** `Peadm::SingleTargetSpec`
- **Description:**  
  The hostname and certname of the replica VM.

### `primary_postgresql_host`

- **Type:** `Optional[Peadm::SingleTargetSpec]`
- **Description:**  
  The target specification for the primary PostgreSQL host that the new replica will synchronize with. This is the database server from which the replica will replicate data.

### `token_file`

- **Type:** `Optional[String]`
- **Description:**  
  Path to token file, only required if located in a non-default location.



## Replica promotion and Replica replacement

Please see the notes on these scenarios in [automated Recovery](automated_recovery.md#recover-from-failed-primary-puppet-server)

