# Backup and restore Puppet Enterprise (PE) 

If your PE installation is managed by `peadm`, you can back up and restore PE using this process:
1. Use the `peadm::backup` plan to create a backup of your primary server.
2. Use the `peadm::restore` plan to restore PE from a `peadm::backup`.

**Important:** If your PE installation is not managed by `peadm`, you cannot use the `peadm::backup` and `peadm::restore` plans. For information on converting to a `peadm` managed installation, see [Convert](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md).  

When running the backup and restore plans, you can define the `backup_type` and `restore_type` parameters with either of the following values:
* `recovery`: Use this type to create a full backup of your primary server, including data for all services. This allows you to restore your primary server and all services (including database services running on external servers) to the exact state they were in at the time of the backup.
* `custom`: Use this type when you want to selectively back up and restore data for specific services. 

If no type is specified, the default is `recovery`.

When backing up or restoring PE, you must use the `--targets` option to specify the hostname (FQDN) of your primary server.
 
The backup file created is named `pe-backup-YYYY-MM-DDTHHMMSSZ.tar.gz` and placed by default in `/tmp`. To specify a different location for the backup file, you can define the `output_directory` parameter.

This example shows how to run a `recovery` backup which places the backup file in a custom location.  
```
bolt plan run peadm::backup --targets my.primary.vm backup_type=recovery output_directory=/custom_path
```

When restoring PE, you must define the `input_file` parameter to specify the path to the backup file you want to use. For example:
```
bolt plan run peadm::restore --targets my.primary.vm input_file="/tmp/my_backup.tar.gz"
```

## Using `recovery` backup and restore

When you run a `recovery` backup plan, the primary server configuration is backed up in full. In the event of a primary server failure, this backup can be used to restore the PE installation to the state it was in when the backup was created.

You can create a `recovery` backup as follows:
```
bolt plan run peadm::backup --targets my.primary.vm backup_type=recovery
```
Alternatively, because `recovery` is the default type, you can use this simplified command:
```
bolt plan run peadm::backup --targets my.primary.vm
```

To restore your installation from this backup, run:
```
bolt plan run peadm::restore --targets my.primary.vm input_file="/tmp/my_backup.tar.gz"
```

**Tip**: Restoring from a `recovery` backup restarts any services that are unavailable on the primary server.

## Using `custom` backup and restore

To specify the items that are backed up and restored, define the `backup_type` or `restore_type` parameters as `custom`.
Otherwise, the default type is `recovery`.

To specify the `custom` items, you can create and reference `params.json` files as shown in the following examples.

To specify custom backup options:
```json
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

To create a backup using the options specified in this parameter file, run:
```
bolt plan run peadm::backup --targets my.primary.vm --params @params.json
```

To specify custom restore options:

```json
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
    "rbac"         : false,
  },
  "input_file" : "/tmp/my_backup.tar.gz"
}
```

To restore PE using the options specified in this parameter file, run:
```
bolt plan run peadm::restore --targets my.primary.vm --params @params.json
```

## What exactly is backed up and restored?

The following table shows the items you can specify and indicates what is included in `recovery`:

| Data or service   | Explanation                                                                                              | Used in `recovery` |
| ------------------| -------------------------------------------------------------------------------------------------------- | ------------------ |
| `activity `       | Activity database                                                                                        |                    |
| `ca `             | CA and ssl certificates                                                                                  | ✅                 |
| `classifier`      | Classifier database. Restore merges user-defined node groups rather than overwriting system node groups. |                    |
| `code`            | Code directory                                                                                           | ✅                 |
| `config`          | Configuration files and databases (databases are restored literally)                                     | ✅                 |
| `orchestrator `   | Orchestrator database                                                                                    |                    |
| `puppetdb`        | PuppetDB database (including support for XL where puppetdb is running on an external db server)          | ✅                 |
| `rbac`            | RBAC database                                                                                            |                    |

**Note**: The `peadm` backup and restore plans utilize the `puppet-backup` tool for backing up and restoring `ca`, `code` and `config`. For `config`, the data backed up includes the `activity`, `classifier`, `orchestrator`, and `rbac` databases.

**Note:** The output for the `peadm::backup` plan differs from the output that is returned when you manually run the [`puppet-backup create` command](https://puppet.com/docs/pe/latest/backing_up_and_restoring_pe.html#back_up_pe_infrastructure).
