# Migrate your Puppet Enterprise (PE) installation  

## Introduction to PEADM migration 

If your PE installation is managed by PEADM, you can migrate your PE installation to new infrastructure using the `peadm::migrate` plan. The plan will perform a backup of your ‘core’ PE infrastructure – primary, primary replica, PE PostgreSQL server, PE PostgreSQL server replica, and then migrate your data and configuration over to the new infrastructure you specify. Once your core infrastructure is migrated you can then move agents and compilers to work with your newly migrated PE installation. 

**Important:** If your PE installation is not managed by PEADM, you cannot use the `peadm::migrate` plan. For information about converting to a PEADM-managed installation, see [Convert](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md).  

 
## Using `migrate` to migrate your PE installation 
When you run the `migrate` plan you will specify the hostname (FQDN) of the old primary server you are migrating from and the replacement infrastructure you are migrating to – this will include the hostname (FQDN) of the new primary, and hostnames of your replica, PE-PostgreSQL server and PE-PostgreSQL replica server if they are present. You can also optionally specify a new PE version to upgrade your migrated PE installation to – the PE version used on the old primary server will be used on the new one of this parameter is not supplied. 

### Running the `migrate` plan 
The plan accepts the following parameters: 

* _\<old_primary_host\>_ - The FQDN and certname of the PE primary server you are migrating from 
* _\<new_primary_host\>_ - The FQDN and certname of the new PE primary server you are migrating to 
* _\<replica_host\>_ - [Optional] The FQDN and certname of the new PE Primary replica server 
* _\<primary_postgresql_host\>_ - [Optional] The FQDN and certname of the new PE PostgreSQL server 
* _\<replica_postgresql_host\>_ - [Optional] The FQDN and certname of the new replica PE PostgreSQL server 
* _\<upgrade_version\>_ - [Optional] The PE version to upgrade to 
* _\<license_key_file\>_ - [Optional] Path to a local PE license file (on the Bolt controller) to install on the new primary. Cannot be combined with `license_key_content` 
* _\<license_key_content\>_ - [Optional] PE license content to install on the new primary. Cannot be combined with `license_key_file` 
* _\<download_mode\>_ - [Optional] How the PE installer reaches the new hosts: `direct` (default) or `bolthost` 
* _\<pe_installer_source\>_ - [Optional] URL of the PE installer for the old primary's PE version 
* _\<upgrade_pe_installer_source\>_ - [Optional] URL of the PE installer for `upgrade_version` 

* _\<keep_backup\>_ - [Optional] Keep the copies of the migration backup on the Bolt controller and the new primary after a successful migration. See [Migration backup](#migration-backup) 

To perform a basic migration from one PE primary server to another run the following command: 
``` 
bolt plan run peadm::migrate old_primary_host=\<old_primary_host\> new_primary_host=\<new_primary_host\> 
``` 

To migrate an Extra Large installation with Disaster Recovery enabled run the following command: 
``` 
bolt plan run peadm::migrate  
old_primary_host=\<old_primary_host\>                         
new_primary_host=\<new_primary_host\> 
replica_host=\<replica_host\> 
primary_postgresql_host=\<primary_postgresql_host\> 
replica_postgresql_host=\<replica_postgresql_host\> 
upgrade_version=2025.2.0 
``` 

Please note, the optional parameters and values of the plan are as follows. 

<!-- table --> 
| Parameter | Default value | Description | 
| ------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------ | 
| `replica_host` | `undef` | By default, no PE replica will be set up unless this value is supplied. | 
| `primary_postgresql_host` | `undef` | By default, no PE PostgreSQL server will be set up unless this value is supplied. | 
| `replica_postgresql_host` | `undef` | By default, no PE PostgreSQL replica server will be set up unless this value is supplied. | 
| `upgrade_version` | `undef` | By default, the new PE installation will be set up with the PE version used on the old primary server. The user can pass in a newer version to upgrade using this parameter, e.g. 2025.1.0 |  
| `license_key_file` | `undef` | By default, the PE license is copied from the old primary server (`/etc/puppetlabs/license.key`, or `/etc/puppetlabs/suite-license.lic` if `license.key` is missing, unreadable, blank, or the task that reads it fails). Supply a local license file to use a different license. See [Licenses](#licenses) for what happens when no license is found. |
| `license_key_content` | `undef` | Same as `license_key_file`, but takes the license text instead of a file path. |
| `download_mode` | `direct` | How the PE installer reaches the new hosts, for both the install and the optional upgrade. `direct` has each new host download the installer itself. `bolthost` downloads the installer to the machine running Bolt and uploads it to the new hosts (for example over SSH), so the new hosts don't need internet access. `bolthost` can't be used with the `pcp` transport. |
| `pe_installer_source` | `undef` | URL to download the PE installer from for the old primary's PE version (the version the new primary is first installed at), e.g. an internal mirror. By default the standard public source is used. |
| `upgrade_pe_installer_source` | `undef` | URL to download the PE installer from for `upgrade_version`. Only used when `upgrade_version` is set. By default the standard public source is used. |

Both installer URLs must end in the standard file name, `puppet-enterprise-<version>-<platform>.tar.gz`, with no query string: `<version>` is the old primary's PE version for `pe_installer_source` and `upgrade_version` for `upgrade_pe_installer_source`, and `<platform>` is the new primary's platform. Before taking the backup, `migrate` checks the file names and checks that each installer can be downloaded from where it will be downloaded (the new hosts, or the Bolt machine with `download_mode=bolthost`), so a wrong URL or missing network access fails the plan before anything has changed. The download check is skipped when the Bolt machine runs Windows.

| `keep_backup` | `false` | By default, the copies of the migration backup on the Bolt controller and the new primary are deleted when the migration succeeds. Set to `true` to keep them. See [Migration backup](#migration-backup). |

### Licenses

When a license is found or supplied, it is installed on the new primary as `/etc/puppetlabs/license.key`. The old primary's license files are only read when neither `license_key_file` nor `license_key_content` is given. The plan fails before anything is changed if both are given, if `license_key_content` is blank, or if `license_key_file` does not exist, cannot be read, or is a blank file.

If no license is found on the old primary, or it cannot be read, the migration continues and the new primary is installed without a license key. The plan prints a message beginning `Warning:` in that case (and another when the migration finishes). It cannot tell a missing file from an unreadable or blank one. If the task that reads the file itself fails, the file path and the task's error message are printed as well, even when the other file then supplies a license.

The license is handled as plain text, as it is by `peadm::install`. Bolt can print it to the terminal when run with `-v` or `--log-level debug` (for example when the plan reads it from the old primary), and it can appear in `bolt-debug.log`, which Bolt writes by default. Protect that log and any captured output when migrating a licensed installation. Supplying `license_key_file` rather than `license_key_content` keeps the license text out of your shell history and the process list.

### Migrating when the new hosts can't reach the internet

By default (`download_mode=direct`), each new host downloads the PE installer itself, so it needs internet access. If the new hosts can't reach the internet, use one of these options.

**Option 1: let the Bolt machine download the installer.** Pass `download_mode=bolthost`. The machine running Bolt downloads each installer and uploads it to the new hosts (for example over SSH), so only that machine needs internet access and about 1 GB of free space in `/tmp` per installer:
```
bolt plan run peadm::migrate
old_primary_host=\<old_primary_host\>
new_primary_host=\<new_primary_host\>
download_mode=bolthost
```

**Option 2: no internet access at all.** Pre-stage the installers on the Bolt machine:
1. Find the old primary's PE version (`cat /opt/puppetlabs/server/pe_version` on the old primary) and the new primary's platform, for example `el-8-x86_64`.
2. On a machine with internet access, download `puppet-enterprise-<version>-<platform>.tar.gz` and its `.asc` signature from `https://s3.amazonaws.com/pe-builds/released/<version>/`. If you set `upgrade_version`, also download the installer for that version.
3. Verify each tarball. PEADM only checks that a staged file exists, not that it's complete or genuine:
   ```
   gpg --verify puppet-enterprise-<version>-<platform>.tar.gz.asc puppet-enterprise-<version>-<platform>.tar.gz
   ```
4. Copy the tarballs to `/tmp` on the Bolt machine (the staging directory used by `peadm::install` and `peadm::upgrade`). Keep the file names exactly as downloaded.
5. Run `migrate` with `download_mode=bolthost`, as in option 1. PEADM uploads the staged tarballs instead of downloading them.

**Option 3: use an internal mirror.** If the new hosts can reach an internal web server, host the installers there and point `pe_installer_source` and `upgrade_pe_installer_source` at them. This works with either `download_mode`:
```
bolt plan run peadm::migrate
old_primary_host=\<old_primary_host\>
new_primary_host=\<new_primary_host\>
upgrade_version=2025.2.0
pe_installer_source=https://mirror.example.com/pe/puppet-enterprise-2023.8.11-el-8-x86_64.tar.gz
upgrade_pe_installer_source=https://mirror.example.com/pe/puppet-enterprise-2025.2.0-el-8-x86_64.tar.gz
```

**Note:** on a Windows Bolt machine, PEADM downloads the installer without checking the server's TLS certificate or the installer's signature. If you run Bolt on Windows, pre-stage installers you have verified, or use a Linux or macOS Bolt machine.

### Migration backup

`migrate` backs up the old primary with `peadm::backup` (`backup_type => migration`) and restores that backup on the new primary. The backup holds PE secrets, including the CA, so treat every copy of it as sensitive. There are three copies:

* on the old primary, as `/tmp/pe-backup-<timestamp>.tar.gz`;
* on the Bolt controller, in the Bolt project's `downloads/backup/<old primary>/` directory;
* on the new primary, as `/tmp/pe-backup-<timestamp>.tar.gz`, which `peadm::restore` also unpacks to `/tmp/pe-backup-<timestamp>/`.

The plan prints where each copy is as soon as they are made. When the migration succeeds, it deletes the copies on the Bolt controller and the new primary, and prints each one it removed. Set `keep_backup` to `true` to keep them; the plan then lists them again at the end. The old primary's copy is never deleted: the plan says where it is, so you can delete it or archive it somewhere safe. If the migration fails, nothing is deleted, so you can retry or clean up using the locations printed earlier.

If a copy cannot be deleted, the migration has still finished, but the plan fails with the error kind `peadm/backup-cleanup-failed` and names each copy that is left. Delete them yourself.

### Code Manager

The new primary keeps the PE Master node group from its own install, not the old one, so `migrate` carries the old primary's Code Manager remote across. It reads these `puppet_enterprise::profile::master` settings from the old PE Master node group, as class parameters or, failing that, configuration data:

* `r10k_remote`
* `r10k_private_key`
* `r10k_known_hosts`, taken from the old primary's `pe.conf` if the node group does not set it. PE's installer does not copy this setting from `pe.conf` into the node group, so a primary installed with `peadm::install`'s `r10k_known_hosts` has it only in `pe.conf`.
* `r10k_git_provider`

It passes them to `peadm::install` as `pe_conf_data`, so they are written to the new primary's `pe.conf` and PE configures Code Manager with them at install. If `r10k_private_key` is set, the key file is copied from the old primary to the same path on the new primary, through the Bolt project's `downloads` directory. Its directory is created if it does not exist, and the key is set to mode 0600; PE then gives it to the `pe-puppet` user at install. The local copy is deleted afterwards, whether or not the copy to the new primary works. If the run is interrupted, or the download itself fails, check `downloads/code-manager-key` in the Bolt project and delete anything left there.

This happens before the backup. The plan stops if it cannot read the old PE Master node group, if any of the settings above has a value of the wrong type (the error names the setting, where it was read from and what was expected), or if the deploy key cannot be copied. Nothing has been backed up or installed at that point, though after a failed key copy the key or its directory may already be on the new primary. Fix the cause and run `migrate` again.

Other Code Manager settings on the old PE Master node group are not carried across. These are the other `r10k_*` and `code_manager_*` settings of `puppet_enterprise::profile::master` (for example `r10k_proxy` or `r10k_postrun`), and any configuration data for `puppet_enterprise::master::code_manager` or `puppet_enterprise::master::code_management`. `code_manager_auto_configure` is the exception: `migrate` always turns Code Manager on. The plan prints a message beginning `Warning:` naming each setting it does not carry, and names them again when the migration finishes. Set them on the new primary after the migration. Apart from `r10k_known_hosts`, the old primary's `pe.conf` is not read for Code Manager settings: PE copies the ones it uses from `pe.conf` into the PE Master node group at install. Settings kept elsewhere, such as Hiera data in your control repository, are not read either. Hiera data in the control repository comes back with your code once you deploy it, if the remote carried across is that repository; check those settings after the first deploy.

The plan's own messages name settings but do not print the remote URL, known hosts or git provider (a failed key copy names the key's path). The task that reads the settings returns them as sensitive values, which Bolt hides in its output, except with `--stream`, which prints the task's raw output first. The settings are then passed to `peadm::install` as plain text, as they would be if you supplied them to `peadm::install` yourself, so they can appear in `bolt-debug.log` and in `-v` output. If your r10k remote URL holds a credential, protect that log and any captured output, and avoid `--stream`.

## What exactly is migrated? 
 
The following table shows the items you can specify and indicates what is included in `migrate`: 
 
| Data or service | Explanation | Used in `migrate` | 
| --------------- | -------------------------------------------------------------------------------------------------------- | ------------------ | 
| `activity` | Activity database | ✅ | 
| `ca ` | CA and ssl certificates | ✅ | 
| `classifier` | Classifier database. Restore merges user-defined node groups rather than overwriting system node groups. | ✅ | 
| `code` | Code directory | | 
| `config` | Configuration files and databases (databases are restored literally) |  | 
| `orchestrator` | Orchestrator database and secrets | ✅ | 
| `puppetdb` | PuppetDB database (including support for XL where puppetdb is running on an external db server) | ✅ | 
| `rbac` | RBAC database and secrets | ✅ | 
