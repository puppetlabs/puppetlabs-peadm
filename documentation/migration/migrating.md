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
* _\<download_mode\>_ - [Optional] How the PE installer reaches the new hosts: `direct` (default) or `bolthost` 
* _\<pe_installer_source\>_ - [Optional] URL of the PE installer for the old primary's PE version 
* _\<upgrade_pe_installer_source\>_ - [Optional] URL of the PE installer for `upgrade_version` 

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
| `download_mode` | `direct` | How the PE installer reaches the new hosts, for both the install and the optional upgrade. `direct` has each new host download the installer itself. `bolthost` downloads the installer to the machine running Bolt and uploads it to the new hosts (for example over SSH), so the new hosts don't need internet access. `bolthost` can't be used with the `pcp` transport. |
| `pe_installer_source` | `undef` | URL to download the PE installer from for the old primary's PE version (the version the new primary is first installed at), e.g. an internal mirror. By default the standard public source is used. |
| `upgrade_pe_installer_source` | `undef` | URL to download the PE installer from for `upgrade_version`. Only used when `upgrade_version` is set. By default the standard public source is used. |

Both installer URLs must end in the standard file name, `puppet-enterprise-<version>-<platform>.tar.gz`, with no query string: `<version>` is the old primary's PE version for `pe_installer_source` and `upgrade_version` for `upgrade_pe_installer_source`, and `<platform>` is the new primary's platform. Before taking the backup, `migrate` checks the file names and checks that each installer can be downloaded from where it will be downloaded (the new hosts, or the Bolt machine with `download_mode=bolthost`), so a wrong URL or missing network access fails the plan before anything has changed. The download check is skipped when the Bolt machine runs Windows.

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
