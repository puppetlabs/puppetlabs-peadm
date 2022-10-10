# Restore Puppet Enterprise using the PEADM module

Once you have a [backup](backup.md) you can restore a PE primary server. It is important to highlight that you can not use the `peadm::restore` plan with a backup that was not created with the `peadm::backup` plan.

**Things to consider**

There is some downtime involved when the `peadm:restore` plan is executed. The following services will be restarted:

1. pe-console-services
2. pe-nginx
3. pxp-agent
4. pe-puppetserver
5. pe-orchestration-services
6. puppet
6. pe-puppetdb

There is also a procedure related to the restoration of the databases where `peadm::restore` will temporarily set privileges (permissions) to a DB user. These temporary privileges are removed right after the PostgreSQL restore command finishes.

## How to use the restore plan?

As in the `peadm::backup` plan, you can choose what you want to restore by specifying the parameter `restore`. The `input_file` parameter refers to the location of the backup tarball.

Example:

```
# restore_params.json

{
  "restore": {
    "orchestrator": false,
    "puppetdb": false,
    "rbac": true,
    "activity": false,
    "ca": false,
    "classifier": false,
  },
  "input_file": "/tmp/path/backup_tarball.tgz"
}
```
To run the `peadm::restore` plan with our custom parameters file, we can do:

    bolt plan run peadm::restore --params @restore_params.json