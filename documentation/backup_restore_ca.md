# Backup and Restore Puppet Enterprise CA

## Overview
Backup and restore plans for the Puppet Enterprise CA. This utilises the [puppet_backup](https://www.puppet.com/docs/pe/2023.4/backing_up_and_restoring_pe.html) tool. This plan has scope set to only CERTS, and will backup CA and SSL certificates. The backup plan will create a tarball of the CA and store it by default in the `/tmp` directory. The restore plan will restore the CA from the tarball at the path you provide.

## Notes
There can be some downtime associated with the restore process. Restore will stop PE services, restore the CA, and then start the PE services. This can take a few minutes.

## Usage

### Backup

```bash
peadm backup_ca target=primary.example.com
```

Backup will output the path to a timestamped folder containing the backup file. The backup file will be named `backup_ca.tgz`. At this stage the backup file can be copied to a safe location.

Optionaly "output_directory" can be specified to change the location of the backup file.

```bash
peadm::backup_ca target=primary.example.com output_directory=/custompath
```

### Restore

```bash
peadm::restore_ca target=primary2.example.com path=/tmp/backup_ca.tgz file_path=/tmp/backup_ca.tgz
```

Restore will stop PE services, restore the CA, and then start the PE services. This can take a few minutes.

Optionaly "recovery_directory" can be specified to change the temporary location where the backup file will be unzipped.

```bash
peadm::restore_ca target=primary2.example.com path=/tmp/backup_ca.tgz file_path=/tmp/backup_ca.tgz recovery_directory=/custompath
```


