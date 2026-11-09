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

### Licenses

When a license is found or supplied, it is installed on the new primary as `/etc/puppetlabs/license.key`. The old primary's license files are only read when neither `license_key_file` nor `license_key_content` is given. The plan fails before anything is changed if both are given, if `license_key_content` is blank, or if `license_key_file` does not exist, cannot be read, or is a blank file.

If no license is found on the old primary, or it cannot be read, the migration continues and the new primary is installed without a license key. The plan prints a message beginning `Warning:` in that case (and another when the migration finishes). It cannot tell a missing file from an unreadable or blank one. If the task that reads the file itself fails, the file path and the task's error message are printed as well, even when the other file then supplies a license.

The license is handled as plain text, as it is by `peadm::install`. Bolt can print it to the terminal when run with `-v` or `--log-level debug` (for example when the plan reads it from the old primary), and it can appear in `bolt-debug.log`, which Bolt writes by default. Protect that log and any captured output when migrating a licensed installation. Supplying `license_key_file` rather than `license_key_content` keeps the license text out of your shell history and the process list.

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
