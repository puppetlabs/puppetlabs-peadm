# Backup and Restore Puppet Enterprise CA

## Overview
Backup and restore plans for the Puppet Enterprise CA. This utilises the [puppet_backup](https://www.puppet.com/docs/pe/2023.4/backing_up_and_restoring_pe.html) tool. This plan has scope set to only CERTS, and will backup CA and SSL certificates. The backup plan will create a tarball of the CA and store it by default in the `/tmp` directory. The restore plan will restore the CA from the tarball at the path you provide.

## Notes
There can be some downtime associated with the restore process. Restore will stop PE services, restore the CA, and then start the PE services. This can take a few minutes.

## Usage

### Backup

```bash
bolt plan run peadm::backup_ca target=primary.example.com
```

Backup returns the path of the backup file, `<output_directory>/pe-backup-<timestamp>/ca_backup.tgz`. The backup file contains the CA private key. It is readable by root only; copy it to a safe location off the primary, then delete the `pe-backup-<timestamp>` folder from the primary.

Optionally, "output_directory" can be specified to change the location of the backup file. It must be an absolute Unix path to a directory that already exists. It should be owned by root and not be writable by other users (or, like `/tmp`, have the sticky bit set); the plan does not check this. The plan creates the timestamped folder inside it with mode `0711`, because on a primary whose CA is stored in the database `puppet-backup` writes part of the backup as the `pe-postgres` user. The `pe-postgres` user must therefore be able to traverse `output_directory` and its parents. Home directories, including `/root`, are usually not traversable, so use a directory such as `/tmp` or a root-owned `/var/backups/pe` with mode `0711`.

```bash
bolt plan run peadm::backup_ca target=primary.example.com output_directory=/custompath
```

On a primary whose CA is stored in the database (for example PE 2025.12.2, 2026.0.1 and 2026.0.2), the plan first runs `puppetserver ca storage --export`, so the CA files in the backup (signed certificates and serial number) match the CA database.

### Restore

First copy the backup file, as root, to the primary you are restoring. Put it in a directory that is owned by root and not writable by other users, such as `/root`, not directly under a shared directory such as `/tmp`, and keep the file owned by root with mode `0600`. Pass its path on that primary as `file_path`.

```bash
bolt plan run peadm::restore_ca target=primary2.example.com file_path=/root/ca_backup.tgz
```

Restore will stop PE services, restore the CA, and then start the PE services. This can take a few minutes.

Optionally, "recovery_directory" can be specified to change the temporary location where the backup file will be unzipped.

```bash
bolt plan run peadm::restore_ca target=primary2.example.com file_path=/root/ca_backup.tgz recovery_directory=/custompath
```
