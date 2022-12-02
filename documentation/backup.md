# Backup Puppet Enterprise using the PEADM module

## What is being backed up?

By default the `peadm::backup` plan will backup the following items:

1. Orchestrator
2. PuppetDB
3. RBAC
   - Also, It copies the LDAP secret key if it present
4. Activity
5. Classification

Optionally you can also backup:

1. CA (CA and SSL certificates)

----

Most of the backups will be a direct copy of the databases with the exception of:

- Classification
  - The backup is done using an API call
- CA
  - The certificate files will be copy via the puppet-backup script.


**Note:** 

It is important to highlight that the `peadm::backup` plan's output is different than the one you will get when you backup manually using [the `puppet-backup create` command.](https://puppet.com/docs/pe/latest/backing_up_and_restoring_pe.html#back_up_pe_infrastructure).

The differences between these two backup tools are:

1. The structure of the backup file, since this plan `peadm:backup` uses a combination of scripts, API calls, and DB backups, you will not be able to restore it using the traditional `sudo puppet-backup restore <backup-filename>` command. [To read more about the difference between the options (flags), please read the official PE doc for backing up & restoring.](https://puppet.com/docs/pe/latest/backing_up_and_restoring_pe.html#back_up_pe_infrastructure)

1. The core idea of the `peadm:backup` plan is a focus on being able to separate customers data from the infrastructure data. This contrasts with the PE backup script which is more focused on a traditional backup and restore after a system failure where will be restoring the same infrastructure. It, therefore, targets things like backing up PostgreSQL rather than the actual data you want.
    - This can be seen when restoring node groups with `peadm:backup` only restores the non-PEinfrastructure source groups and restores them to target.

    - [PE backup](https://puppet.com/docs/pe/latest/backing_up_and_restoring_pe.html#back_up_pe_infrastructure) is not capable of restoring to a DR setup and requires you to provision a new DR setup whereas [`peadm:restore`](restore.md) will reinitialise replicas as part of the process

1. One of the other key differences with the `peadm:backup` is it is compatible with the extra-large (XL) architectures as it can communicate with the remote PostgreSQL server using temporary escalated privileges.

## How can I customize my backup?

We need to pass the `backup` parameter to the `peadm::backup` plan.

**Example**

**Note:** The `peadm::backup` plan can only be executed from the PE primary server.

Let's Backup _only_ RBAC

```
# backup_params.json

{
  "backup": {
    "orchestrator": false,
    "puppetdb": false,
    "rbac": true,
    "activity": false,
    "ca": false,
    "classifier": false
  },
  "output_directory": "/tmp"
}
```

We selected our backup options and the `output_directory` (default `/tmp`).

To run the backup plan with our custom parameters:

    bolt plan run peadm::backup --params @backup_params.json

