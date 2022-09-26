# Backup Puppet Enterprise using the peadm module

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

**Note:** It is important to note that the `peadm::backup` plan in its current version is not as granular as you can get when you manually run [the `puppet-backup create` command.](https://puppet.com/docs/pe/2021.7/backing_up_and_restoring_pe.html#back_up_pe_infrastructure)

## How can I customize my backup?

We need to pass the `backup` parameter to the `peadm::backup` plan.

**Example**

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

