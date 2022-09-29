# Restore Puppet Enterprise using the PEADM module

Once you have a [backup](backup.md) you can restore a PE primary server. It is important to highlight that you can not use the `peadm::restore` plan with a backup that was not created with the `peadm::backup` plan.

As in the `peadm::backup` plan, you can choose what you want to restore by specifying the parameter `restore`

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
  "input_file": "/tmp/path"
}
```
To run the `peadm::restore` plan with our custom parameters file, we can do:

    bolt plan run peadm::restore --params @restore_params.json