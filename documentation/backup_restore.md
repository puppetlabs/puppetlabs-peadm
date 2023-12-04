# Backup and Restore Puppet Enterprise using the PEADM module

## Introduction

The PEADM backup and restore supports two types: `recovery` and `custom`.
You can select the type by providing the parameter `backup_type` for backup and `restore_type` for restore.
`recovery` is the default backup/restore type.

The backup file will be named `pe-backup-YYYY-MM-DDTHHMMSSZ.tar.gz` and placed in `/tmp` by default. The output directory can be overridden with
the parameter `output_directory`.

The restore needs to specify the backup file path to restore from in its `input_file` parameter.

**Important note**: peadm backup and restore can only be used on PE installs which are created using PEADM. Also, you can only use `peadm::restore` on a backup created by `peadm::backup`.

A backup and restore need to specify the primary server as the target.

## Recovery backup type

When backup type `recovery` is selected, the primary backup created is intended to be used to recover the primary it if it fails. This means that the primary's configuration will be restored to exactly the state it was in when the backup was created.

You can create a recovery backup as follows:
```
bolt plan run peadm::backup --targets my.primary.vm backup_type=recovery
```
or, simply,
```
bolt plan run peadm::backup --targets my.primary.vm
```

To restore from this backup, you can do:
```
bolt plan run peadm::restore --targets my.primary.vm input_file="/tmp/my_backup.tar.gz"
```

The recovery restore will also work if some or all services are down on the primary. The restore process will restart the services at the end.

## Custom backup type

When selecting the `custom` backup type, the user can choose which items are backed up and/or restored using the `backup` (or `restore`) plan parameter.
This parameter can be omitted, in which case all options will be turned on by default.

To specify custom backup (restore) options, it is best to create a `params.json` file like follows:

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

To backup using this parameter file, do:
```
bolt plan run peadm::backup --targets my.primary.vm --params @params.json
```

or, for restore,

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

To restore using this parameter file, do:
```
bolt plan run peadm::restore --targets my.primary.vm --params @params.json
```

## What exactly is backed up and restored?

These are the explanations of the different backup/restore items:

| Item         | Comments                                                                                               | Used in `recovery` |
| ------------ | ------------------------------------------------------------------------------------------------------ | ------------------ |
| activity     | Activity database                                                                                      |                    |
| ca           | CA and ssl certificates                                                                                | ✅                  |
| classifier   | Classifier database. Restore will merge user-defined node groups and not overwrite system node groups. |                    |
| code         | Code directory                                                                                         | ✅                  |
| config       | Configuration files and databases (databases are restored literally)                                   | ✅                  |
| orchestrator | Orchestrator database                                                                                  |                    |
| puppetdb     | PuppetDB database (including support for XL where puppetdb is running on an external db server)        | ✅                  |
| rbac         | RBAC database                                                                                          |                    |

**Note**: `ca`, `code` and `config` are backed up using the `puppet-backup create` command and restored using the `puppet-backup restore` command. 
The `config` item includes backups of `activity`, `classifier`, `orchestrator` and `rbac` databases.

**Note:** It is important to highlight that the `peadm::backup` plan's output is different than the one you will get when you backup manually using [the `puppet-backup create` command.](https://puppet.com/docs/pe/latest/backing_up_and_restoring_pe.html#back_up_pe_infrastructure).