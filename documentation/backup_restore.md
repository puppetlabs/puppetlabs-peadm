# Backup and restore Puppet Enterprise (PE) 

- [Backup and restore Puppet Enterprise (PE)](#backup-and-restore-puppet-enterprise-pe)
  - [Introduction to PEADM backup and restore](#introduction-to-peadm-backup-and-restore)
  - [Using `recovery` backup and restore](#using-recovery-backup-and-restore)
  - [Using `custom` backup and restore](#using-custom-backup-and-restore)
  - [What exactly is backed up and restored?](#what-exactly-is-backed-up-and-restored)
  - [Recovering a primary server when some or all services are not operational](#recovering-a-primary-server-when-some-or-all-services-are-not-operational)
  - [Recovering a non-operational database server in an extra-large installation](#recovering-a-non-operational-database-server-in-an-extra-large-installation)

## Introduction to PEADM backup and restore

If your PE installation is managed by PEADM, you can back up and restore PE using this process:
1. Use the `peadm::backup` plan to create a backup of your primary server.
2. Use the `peadm::restore` plan to restore PE from a `peadm::backup`.

**Important:** If your PE installation is not managed by PEADM, you cannot use the `peadm::backup` and `peadm::restore` plans. For information about converting to a PEADM-managed installation, see [Convert](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md).  

You can specify the type of backup or restore plan you want to use. There are two types:  
-	`recovery`: Use this type to create a full backup of your primary server, including data for all services. The recovery option allows you to restore your primary server and all services (including database services running on external servers) to the exact state they were in at the time of the backup.
-	`custom`: Use this type when you want to back up and restore data for specific services.

If no type is specified, the default is `recovery`.

**Important**: When restoring your installation, the hostname of the primary server you are restoring to _must be the same as_ the hostname of the primary server you created the backup from.
You cannot successfully restore your installation if you change the hostname of your primary server during the recovery process.

## Using `recovery` backup and restore

When you run a `recovery` backup plan, the primary server configuration is backed up in full. In the event of a primary server failure, this backup can be used to to restore your primary server and all services (including database services running on external servers) to the exact state they were in at the time of the backup.

### Create a `recovery` backup
Run one of the following commands:
- To create the backup file in the default location, run the `peadm::backup` plan, including the `--targets` option to specify the hostname (FQDN) of your primary server:
```
bolt plan run peadm::backup --targets my.primary.vm backup_type=recovery
```
- Alternatively, because `recovery` is the default type, you can use this simplified command:
```
bolt plan run peadm::backup --targets my.primary.vm
```
- To place the backup file in a custom location, define the `output_directory` parameter. For example:
```
bolt plan run peadm::backup --targets my.primary.vm backup_type=recovery output_directory=/custom_path
```
### Restore your installation from a `recovery` backup
Run the `peadm::restore` plan, including the `--targets` option to specify the hostname (FQDN) of your primary server and defining the `input_file` parameter to specify the path to the backup file you want to use. For example.  
```
bolt plan run peadm::restore --targets my.primary.vm input_file="/tmp/my_backup.tar.gz"
```
**Note**: Restoring from a `recovery` backup restarts any services that are unavailable on the primary server.

## Using `custom` backup and restore
### Create a `custom` backup.
To customize the items you back up, first create a JSON file in which you define the `backup_type` parameter as `custom` and define the `backup` parameter by specifying which items you want to exclude. For example:
```
{
  "backup_type" : "custom",
  "backup": {
    "activity"     : false,
    "ca"           : true,
    "classifier"   : false,
    "code"         : true,
    "config"       : true,
    "orchestrator" : false,
    "puppetdb"     : true,
    "rbac"         : false
  }
}
```
When you have created the JSON file specifying your custom backup, run the `peadm::backup` plan, including the `--params` option and specifying the relevant filename (and file path if necessary). For example:  
```
bolt plan run peadm::backup --targets my.primary.vm --params @params.json
```
### Restore custom items
To customize the items you restore, create a JSON file in which you define the `restore_type` parameter as `custom`, define the `restore` parameter by specifying the items you want to exclude, and define the `input_file` parameter by specifying the path to the relevant backup file. For example,
```
{
  "restore_type" : "custom",
  "restore": {
    "activity"     : false,
    "ca"           : true,
    "classifier"   : false,
    "code"         : true,
    "config"       : true,
    "orchestrator" : false,
    "puppetdb"     : true,
    "rbac"         : false
  },
  "input_file" : "/tmp/my_backup.tar.gz"
}
```

When you have created the JSON file specifying your custom restore options, run the `peadm::restore` plan, including the `--params` option and specifying the relevant filename (and file path if necessary). For example:
```
bolt plan run peadm::restore --targets my.primary.vm --params @params.json
```

## What exactly is backed up and restored?

The following table shows the items you can specify and indicates what is included in `recovery`:

| Data or service | Explanation                                                                                              | Used in `recovery` |
| --------------- | -------------------------------------------------------------------------------------------------------- | ------------------ |
| `activity `     | Activity database                                                                                        |                    |
| `ca `           | CA and ssl certificates                                                                                  | ✅                  |
| `classifier`    | Classifier database. Restore merges user-defined node groups rather than overwriting system node groups. |                    |
| `code`          | Code directory                                                                                           | ✅                  |
| `config`        | Configuration files and databases (databases are restored literally)                                     | ✅                  |
| `orchestrator ` | Orchestrator database and secrets                                                                        |                    |
| `puppetdb`      | PuppetDB database (including support for XL where puppetdb is running on an external db server)          | ✅                  |
| `rbac`          | RBAC database and secrets                                                                                |                    |

**Note**: The PEADM backup and restore plans utilize the `puppet-backup` tool for backing up and restoring `ca`, `code` and `config`. For `config`, the data backed up includes the `activity`, `classifier`, `orchestrator`, and `rbac` databases.

**Note:** The output for the `peadm::backup` plan differs from the output that is returned when you manually run the [`puppet-backup create` command](https://puppet.com/docs/pe/latest/backing_up_and_restoring_pe.html#back_up_pe_infrastructure).

## Recovering a primary server when some or all services are not operational

**Important**: To complete the recovery process outlined here, you must have a recovery backup of your primary server.

If you cannot run the `recovery` restore plan directly because your primary server is not operational, you can use the following process to restore PE:
1. On the node hosting the affected primary server, uninstall and reinstall PE, ensuring that you re-install the same PE version. Optionally, you can use the `peadm::reinstall_pe` task as follows:
    ```
    bolt task run peadm::reinstall_pe --targets my.primary.vm uninstall=true version=2023.5.0
    ```
1. Perform a `recovery` restore of your primary server, specifying the backup file that you want to use. For example:
    ```
    bolt plan run peadm::restore --targets my.primary.vm input_file="/tmp/my_backup.tar.gz" restore_type=recovery
    ```

## Recovering a non-operational database server in an extra-large installation

**Important**: To complete the recovery process outlined here, you must have a recovery backup of your primary server.

When your primary database server is not operational, you might not be able to use the `recovery` restore directly because the puppetdb database service will not be operational. In this case, follow the steps below to restore your primary database:

1. Reinstall Puppet Enterprise on the affected database server and reconfigure and re-sign its certificate. Make sure you are installing the same PE version as your current primary server was running.
To do this, use the plan `peadm::util::init_db_server` as follows:
    ```
    bolt plan run peadm::util::init_db_server db_host=my.primary_db.vm pe_version=2023.5.0 install_pe=true pe_platform=el-8-x86_64
    ```

    This plan performs the following tasks:

     1. Cleans the current certificate for the database server from the primary server.
     1. Requests a new certificate for the database server with the right extensions (`peadm_role = puppet/puppetdb-database`, `peadm_availability_group=A`).
     1. Stops the puppetdb service on the compilers.
     1. Prepares a `pe.conf` file on the database server for database installation
     1. Installs PE on the database server using the generated `pe.conf` file.
     1. Configures the database as the primary puppetdb database in the XL installation.
     1. Runs puppet on the compilers to allow puppetdb on the compilers to be reconfigured with the new primary database server.
     1. Starts the puppetdb service on the compilers.
     1. Restarts the puppetserver service on the compilers.

1. Perform a `recovery-db` restore of your database server, specifying the backup file that you want to use. For example:
    ```
    bolt plan run peadm::restore --targets my.primary.vm input_file="/tmp/my_backup.tar.gz" restore_type=recovery-db
    ```
   **Important**: You must use the `restore_type=recovery-db` parameter to recover the database server.
   
   **Important**: You must specify the primary server host node (not the database server host node) as the target for the restore plan.
