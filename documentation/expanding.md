# Expanding your deployment

Documentation which provides instructions for expanding existing PEADM based deployments of Puppet Enterprise with compilers, disaster recovery replicas, and external databases.

- [Adding External Databases with peadm::add_database](#adding-external-databases-with-peadmadd_database)
- [Enable Disaster Recovery and Add a Replica with peadm::add_replica](#enable-disaster-recovery-and-add-a-replica-with-peadmadd_replica)
- [Adding Compilers with peadm::add_compilers](#adding-compilers-with-peadmadd_compilers)

### Notes

- CLI options for `add_replica`, `add_compilers`, and `add_database` are unfortunately inconsistent
  - This is the result of a history of organic development
- There is an inconsistency in the output of the task `peadm::get_peadm_config` and the naming of related parameters
  - The documentation and CLI refer to availability groups but the output from the task will refer to associated data as role letters
- The term host and server are interchangeable throughout the documentation
  - When ever possible documentation will prefer the term server but plan parameters and `peadm::get_peadm_config` often uses the term host

### Key

- _\<primary-server-fqdn\>_ - The FQDN and certname of the Primary Puppet server
- _\<new-postgres-server-fqdn\>_ - The FQDN and certname of the new PE-PostgreSQL server to initialize
- _\<new-replica-server-fqdn\>_ - The FQDN and certname of the new Replica Puppet server to initialize
- _\<replica-postgres-server-fqdn\>_ - The FQDN and certname of the Replica PE-PostgreSQL server
- _\<new-compiler-fqdn\>_ - The FQDN and certname of the new Compiler to initialize
- _\<new-compiler-target-group\>_ - The target availability group letter to assign to the new Compiler
- _\<target-group-server-fqdn\>_ - The FQDN and certname of the Primary Puppet server that is assigned to the new Compiler's target availability group letter
- _\<target-group-postgresql-fqdn\>_ - The FQDN and certname of the PE-PostgreSQL server that is assigned to the new Compiler's target availability group letter

## Adding External Databases with peadm::add_database

An external PE-PostgreSQL server is the component which separates the Extra Large and Large deployment architectures. These external database servers are PuppetDB specific and do not serve databases for other components of Puppet Enterprise. When the Extra Large deployment architecture is being utilized and disaster recovery (DR) is enabled, two external PE-PostgreSQL servers must be provisioned and it is required that both PE-PostgreSQL servers exist prior to provisioning a Replica Puppet server because it is immediately dependent upon this second external database server. In both situations, with **no DR** plans and when preparing to enable it for the first time, the command is exactly the same. This specific plan is intelligent enough to determine the most appropriate values for your second external PE-PostgreSQL server by examining the values which were used for the first.

### Add an external PE-PostgreSQL server in all scenarios

    bolt plan run peadm::add_database -t <new-postgres-server-fqdn> primary_host=<primary-server-fqdn>

## Enable Disaster Recovery and Add a Replica with peadm::add_replica

All three deployment architectures have two variations, disaster recovery (DR) enabled or disabled. The deployment architecture a Puppet Enterprise deployment adopts is not changed by the addition of a Replica Puppet server. If you adopt the Standard deployment architecture and enable DR by provisioning a Replica Puppet server, the adopted deployment architecture remains as Standard. The basic process is also the same when adding a Replica Puppet server to any existing PEADM based deployment of Puppet Enterprise but there are differences in CLI arguments when operating on the Extra Large deployment architecture.

PEADM creates availability groups to logically group failure domains within a Puppet Enterprise deployment. These availability group designations control how various components connect together with backend services like database servers. Availability group **A** is created by PEADM in all scenarios but when you enable DR using PEADM, a second availability group will be created, **B**.

The initial Primary will be assigned availability group **A** and the initial Replica is assigned **B**. The availability group assignments stay with the server and importantly not with the role of the server. If you choose to promote the Replica Puppet server assigned to **B** to a Primary than availability group **B** is now simply the group containing the Primary Puppet server. When adding a Replica Puppet server you do not need to know the availability group of the Primary it is being paired with, the `peadm::add_replica` plan will determine the appropriate group by looking up to which group the Primary Puppet server is assigned.

### Adding a Replica to Standard and Large deployments

    bolt plan run peadm::add_replica primary_host=<primary-server-fqdn> replica_host=<new-replica-server-fqdn>

### Adding a Replica to Extra Large deployments

In deployments which adopted the Extra Large deployment architecture you must provide the `replica_postgresql_host` parameter set to the PE-PostgreSQL server which will be collocated within the same availability group as the new Replica Puppet server. The `peadm::get_peadm_config` task will help you determine the most appropriate value. In the **Example** section below, the task has figured out which PE-PostgreSQL server is the Replica PE-PostgreSQL database server. You'll find the value at `params.replica_postgresql_host`, which is equal to `pe-psql-6251cd-1.us-west1-b.c.slice-cody.internal`. Reminder, the Replica PE-PostgreSQL server **MUST** be provisioned and deployed prior to initializing a Replica Puppet server.

    bolt task run peadm::get_peadm_config --targets <primary-server-fqdn>
    bolt plan run peadm::add_replica primary_host=<primary-server-fqdn> replica_host=<new-replica-server-fqdn> replica_postgresql_host=<replica-postgres-server-fqdn>

**Example**

    % bolt task run peadm::get_peadm_config --targets pe-server-6251cd-0.us-west1-a.c.slice-cody.internal                                           -- INSERT --
    Started on pe-server-6251cd-0.us-west1-a.c.slice-cody.internal...
    Finished on pe-server-6251cd-0.us-west1-a.c.slice-cody.internal:
      {
        "params": {
          "primary_host": "pe-server-6251cd-0.us-west1-a.c.slice-cody.internal",
          "replica_host": null,
          "primary_postgresql_host": "pe-psql-6251cd-0.us-west1-a.c.slice-cody.internal",
          "replica_postgresql_host": "pe-psql-6251cd-1.us-west1-b.c.slice-cody.internal",
          "compilers": [
            "pe-compiler-6251cd-0.us-west1-a.c.slice-cody.internal",
            "pe-compiler-6251cd-1.us-west1-b.c.slice-cody.internal"
          ],
          "compiler_pool_address": "puppet.pe-compiler-lb-6251cd.il4.us-west1.lb.slice-cody.internal",
          "internal_compiler_a_pool_address": "pe-server-6251cd-0.us-west1-a.c.slice-cody.internal",
          "internal_compiler_b_pool_address": null
        },
        "role-letter": {
          "server": {
            "A": "pe-server-6251cd-0.us-west1-a.c.slice-cody.internal",
            "B": null
          },
          "postgresql": {
            "A": "pe-psql-6251cd-0.us-west1-a.c.slice-cody.internal",
            "B": "pe-psql-6251cd-1.us-west1-b.c.slice-cody.internal"
          },
          "compilers": {
            "A": [
              "pe-compiler-6251cd-0.us-west1-a.c.slice-cody.internal",
              "pe-compiler-6251cd-1.us-west1-b.c.slice-cody.internal"
            ],
            "B": [

            ]
          }
        }
      }
    Successful on 1 target: pe-server-6251cd-0.us-west1-a.c.slice-cody.internal
    Ran on 1 target in 2.56 sec

## Adding Compilers with peadm::add_compilers

The Standard deployment architecture is the only deployment architecture of the three which does not include Compilers, the lack of them is what differentiates the Standard from Large deployment architecture. Deployment architecture has no effect on the process for adding Compilers to a deployment. The [peadm::add_compilers](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/plans/add_compilers.pp) plan functions identical in all three deployment architectures, whether you are adding the 1st or the 100th but some options do change slightly depending.

### Adding Compilers to Standard and Large without disaster recovery

The command invocation is identical when adding Compilers to a Standard or Large deployment architecture if disaster recovery (DR) is not enabled and a replica Puppet server has not been provisioned. Take note that `avail_group_letter` is not required in this **no DR** scenario. By default, the value of this parameter is set to **A**.

    bolt plan run peadm::add_compilers primary_host=<primary-server-fqdn> compiler_hosts=<new-compiler-fqdn>

### Adding Compilers to Extra Large without disaster recovery

When adding a compiler to a deployment which has adopted the Extra Large deployment architecture in a **no DR** scenario, the only difference is that the `primary_postgresql_host` changes to the value of the primary PE-PostgreSQL server as opposed to the Primary Puppet server.

    bolt plan run peadm::add_compilers primary_host=<primary-server-fqdn> compiler_hosts=<new-compiler-fqdn>

### Adding Compilers to Standard and Large when disaster recovery has been enabled

As was described in the section documenting [peadm::add_replica](#enable-disaster-recovery-and-add-a-replica-with-peadmadd_replica), when disaster recovery (DR) is enabled and a Replica provisioned, PEADM creates a second availability group, **B**. You must take this second availability group into consideration when adding new compilers and ensure you are assigning appropriate values for the group the compiler is targeted for. It is a good idea to keep these two availability groups populated with an equal quantity of compilers. Besides the value of `avail_group_letter` being dependent on which group the new compiler is targeted towards, the value of `primary_postgresql_host` will also vary.

The name of the `primary_postgresql_host` parameter can be confusing, it is **NOT** always equal to the Primary Puppet server or Primary PE-PostgreSQL server, it can also be equal to the replica Puppet server or replica PE-PostgreSQL server. It should be set to the server which is a member of the compiler's target availability group. In most cases this will be handled behind the scenes and not be required to be worked out by the user. The easiest way to determine this value is to first run the `peadm::get_peadm_config` task and source the value from its output. In the **Example** section the value to use when targeting the **B** group is `pe-server-59ab63-1.us-west1-b.c.slice-cody.internal`. You'll find the value at `role-letter.server.B`.

    bolt plan run peadm::get_peadm_config --targets <primary-server-fqdn>
    bolt plan run peadm::add_compilers primary_host=<primary-server-fqdn> compiler_hosts=<new-compiler-fqdn> avail_group_letter=<new-compiler-target-group> primary_postgresql_host=<target-group-server-fqdn>

**Example**

    % bolt task run peadm::get_peadm_config --targets pe-server-59ab63-0.us-west1-a.c.slice-cody.internal
    Started on pe-server-59ab63-0.us-west1-a.c.slice-cody.internal...
    Finished on pe-server-59ab63-0.us-west1-a.c.slice-cody.internal:
      {
        "params": {
          "primary_host": "pe-server-59ab63-0.us-west1-a.c.slice-cody.internal",
          "replica_host": "pe-server-59ab63-1.us-west1-b.c.slice-cody.internal",
          "primary_postgresql_host": null,
          "replica_postgresql_host": null,
          "compilers": [
            "pe-compiler-59ab63-0.us-west1-a.c.slice-cody.internal",
            "pe-compiler-59ab63-1.us-west1-b.c.slice-cody.internal"
          ],
          "compiler_pool_address": "puppet.pe-compiler-lb-59ab63.il4.us-west1.lb.slice-cody.internal",
          "internal_compiler_a_pool_address": "pe-server-59ab63-0.us-west1-a.c.slice-cody.internal",
          "internal_compiler_b_pool_address": "pe-server-59ab63-1.us-west1-b.c.slice-cody.internal"
        },
        "role-letter": {
          "server": {
            "A": "pe-server-59ab63-0.us-west1-a.c.slice-cody.internal",
            "B": "pe-server-59ab63-1.us-west1-b.c.slice-cody.internal"
          },
          "postgresql": {
            "A": null,
            "B": null
          },
          "compilers": {
            "A": [
              "pe-compiler-59ab63-0.us-west1-a.c.slice-cody.internal"
            ],
            "B": [
              "pe-compiler-59ab63-1.us-west1-b.c.slice-cody.internal"
            ]
          }
        }
      }
    Successful on 1 target: pe-server-59ab63-0.us-west1-a.c.slice-cody.internal
    Ran on 1 target in 2.46 sec

### Adding Compilers to Extra Large when disaster recovery has been enabled

Adding a Compiler to a deployment which has adopted the Extra Large deployment architecture with disaster recovery (DR) enabled is similar to Standard and Large but the value of `primary_postgresql_host` will no longer correspond to the Primary or Replica Puppet server since PuppetDB databases are now hosted externally. In the **Example** section, the value to use when targeting the **A** group is `pe-psql-65e03f-0.us-west1-a.c.slice-cody.internal`. You'll find the value at `role-letter.postgresql.A`.

    bolt plan run peadm::get_peadm_config --targets <primary-server-fqdn>
    bolt plan run peadm::add_compilers primary_host=<primary-server-fqdn> compiler_hosts=<new-compiler-fqdn> avail_group_letter=<new-compiler-target-availability-group> primary_postgresql_host=<target-availability-group-postgresql-fqdn>

**Example**

    % bolt task run peadm::get_peadm_config --targets pe-server-65e03f-0.us-west1-a.c.slice-cody.internal
    Started on pe-server-65e03f-0.us-west1-a.c.slice-cody.internal...
    Finished on pe-server-65e03f-0.us-west1-a.c.slice-cody.internal:
      {
        "params": {
          "primary_host": "pe-server-65e03f-0.us-west1-a.c.slice-cody.internal",
          "replica_host": "pe-server-65e03f-1.us-west1-b.c.slice-cody.internal",
          "primary_postgresql_host": "pe-psql-65e03f-0.us-west1-a.c.slice-cody.internal",
          "replica_postgresql_host": "pe-psql-65e03f-1.us-west1-b.c.slice-cody.internal",
          "compilers": [
            "pe-compiler-65e03f-0.us-west1-a.c.slice-cody.internal"
          ],
          "compiler_pool_address": "puppet.pe-compiler-lb-65e03f.il4.us-west1.lb.slice-cody.internal",
          "internal_compiler_a_pool_address": "pe-server-65e03f-0.us-west1-a.c.slice-cody.internal",
          "internal_compiler_b_pool_address": "pe-server-65e03f-1.us-west1-b.c.slice-cody.internal"
        },
        "role-letter": {
          "server": {
            "A": "pe-server-65e03f-0.us-west1-a.c.slice-cody.internal",
            "B": "pe-server-65e03f-1.us-west1-b.c.slice-cody.internal"
          },
          "postgresql": {
            "A": "pe-psql-65e03f-0.us-west1-a.c.slice-cody.internal",
            "B": "pe-psql-65e03f-1.us-west1-b.c.slice-cody.internal"
          },
          "compilers": {
            "A": [
              "pe-compiler-65e03f-0.us-west1-a.c.slice-cody.internal"
            ],
            "B": [
              "pe-compiler-65e03f-1.us-west1-b.c.slice-cody.internal"
            ]
          }
        }
      }
    Successful on 1 target: pe-server-65e03f-0.us-west1-a.c.slice-cody.internal
    Ran on 1 target in 2.35 sec
