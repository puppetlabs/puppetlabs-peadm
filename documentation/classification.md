# PE Extra Large architecture classification #

## Overview

This reference implementation uses four non-default node classification groups to implement the Extra Large HA architecture. Intentionally, classification of default, out-of-box node groups is not modified. This allows normal commands such as `puppet infrastructure enable replica` to behave more or less exactly as they would in Standard or Large architecture deployments.

This image shows a fully expanded view of the PE Infrastructure node group, highlighting the new additions made to support the Extra Large archtecture.

![PE Classification tree](images/pe-xl-classification.png)

## Node Groups

The new groups are:

* PE Master A
* PE Master B
* PE Compiler Group A
* PE Compiler Group B

The configuration applied in each group looks as follows:

### PE Master A

![PE Master A group](images/pe-master-a.png)

Notes for PE Master A:

* The (initial) Master is the only member of this node group
* Sets as data two parameters
    * `puppet_enterprise::profile::master_replica::database_host_puppetdb`
    * `puppet_enterprise::profile::puppetdb::database_host`
* Sets both parameters to the name of the PuppetDB PostgreSQL node paired with this master
* Uses a different PuppetDB PostgreSQL node than PE Master B

### PE Master B
![PE Master B group](images/pe-master-b.png)

Notes for PE Master B:

* The (initial) Master Replica is the only member of this node group
* Sets as data two parameters
    * `puppet_enterprise::profile::master_replica::database_host_puppetdb`
    * `puppet_enterprise::profile::puppetdb::database_host`
* Sets both parameters to the name of the PuppetDB PostgreSQL node paired with this master
* Uses a different PuppetDB PostgreSQL node than PE Master A

### PE Compiler Group A
![PE Compiler Group A group](images/pe-compiler-group-a.png)

Notes for PE Compiler Group A:

* Half of the compilers are members of this group
* Applies the `puppet_enterprise::profile::puppetdb` class
* Sets the `puppet_enterprise::profile::puppetdb::database_host` parameter
    * Should be set to `"pdb-pg-a"`, where "pdb-pg-a" is the name of the PuppetDB PostgreSQL database host paired with the (initial) Master
* Modifies the `puppet_enterprise::profile::master::puppetdb_host` parameter
    * Should be set to `[${clientcert}, "master-b"]`, where "master-b" is the name of the (initial) Master Replica.
    * If you have a load balancer for the compilers in PE Compiler Group B port 8081, you should use that load balancer address instead of "master-b"
* Modifies the `puppet_enterprise::profile::master::puppetdb_port` parameter
    * Should be set to `[8081]`

### PE Compiler Group B
![PE Compiler Group B group](images/pe-compiler-group-b.png)

Notes for PE Compiler Group B:

* The other half of the compilers (those not in the PE Compiler Group A node group) are members of this group
* Applies the `puppet_enterprise::profile::puppetdb` class
* Sets the `puppet_enterprise::profile::puppetdb::database_host` parameter
    * Should be set to `"pdb-pg-b"`, where "pdb-pg-b" is the name of the PuppetDB PostgreSQL database host paired with the (initial) Master Replica
* Modifies the `puppet_enterprise::profile::master::puppetdb_host` parameter
    * Should be set to `[${clientcert}, "master-a"]`, where "master-a" is the name of the PuppetDB PostgreSQL node paired with the (initial) Master Replica.
    * If you have a load balancer for the compilers in PE Compiler Group A port 8081, you should use that load balancer address instead of "master-a"
* Modifies the `puppet_enterprise::profile::master::puppetdb_port` parameter
    * Should be set to `[8081]`
