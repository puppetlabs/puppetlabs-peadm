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
