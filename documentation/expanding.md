# Expanding your deployment

Documentation which provides instructions for expanding existing PEADM based deployments of Puppet Enterprise with compilers, disaster recovery replicas, and external databases.

* [Adding External Databases with peadm::add_database](#adding-external-databases-with-peadmadd_database)
* [Enable Disaster Recovery and Add a Replica with peadm::add_replica](#enable-disaster-recovery-and-add-a-replica-with-peadmadd_replica)
* [Adding Compilers with peadm::add_compiler](#adding-compilers-with-peadmadd_compiler)

### Key
* _\<primary-server-fqdn\>_ - The FQDN and certname of the Primary Puppet server
* _\<new-postgres-server-fqdn\>_ - The FQDN and certname of the new PE-PostgreSQL server to initialize
* _\<new-replica-server-fqdn\>_ - The FQDN and certname of the new Replica Puppet server to initialize
* _\<replica-postgres-server-fqdn\>_ - The FQDN and certname of the Replica PE-PostgreSQL server
* _\<new-compiler-fqdn\>_ - The FQDN and certname of the new Compiler to initialize
* _\<new-compiler-target-group\>_ - The target availability group letter to assign to the new Compiler
* _\<target-group-server-fqdn\>_ - The FQDN and certname of the Primary Puppet server that is assigned to the new Compiler's target availability group letter
* _\<target-group-postgresql-fqdn\>_ - The FQDN and certname of the PE-PostgreSQL server that is assigned to the new Compiler's target availability group letter

## Adding External Databases with peadm::add_database

An external PE-PostgreSQL database is the component which separates Extra Large from Large deployments. These external database servers are PuppetDB specific and do not serve any other data storage services to other components of Puppet Enterprise. When the Extra Large architecture is being utilized and disaster recovery (DR) is enabled, two external PE-PostgreSQL servers must be provisioned and it is required that both PE-PostgreSQL servers exist prior to provisioning a Replica because it is immediately dependent upon this second external database server. One should notice that in both variations of this action, with **no DR** plans and when preparing to enable it for the first time, the command is exactly the same. This specific plan is intelligent enough to determine the most appropriate values for your second external database by examining the values which were used for the first.

### Add an external PE-PostgreSQL server in all scenarios

    bolt plan run peadm::add_database -t <new-postgres-server-fqdn> primary_host=<primary-server-fqdn>

## Enable Disaster Recovery and Add a Replica with peadm::add_replica

All three architectures have two variations, disaster recovery (DR) enabled or disabled. This does not have an effect on the deployed architecture naming, a Standard deployment which deploys a DR Replica is still referred to as the Standard architecture. The basic process remains the same when adding a Replica to any architecture but there are differences in CLI arguments when operating on an Extra Large deployment. When DR is enabled using PEADM, a second availability group will be created, **B**. When DR is not enabled, only one exists, **A**. These availability groups are created for pairing subsets of Compilers with the backend source which will configure them, among other things. By default the initial Primary is assigned availability group **A** and the initial Replica is assigned **B**. The availability group assignments stay with the server and importantly not with the role of the server. If you choose to promote the Replica assigned to **B** to a Primary than availability group **B** is now simply the group containing the Primary. When adding a Replica you do not need to know the availability group of the Primary it is being paired with, the `peadm::add_replica` plan will determine the appropriate group by looking up which group the Primary is assigned.

### Adding a Replica to Standard and Large deployments

    bolt plan run peadm::add_replica primary_host=<primary-server-fqdn> replica_host=<new-replica-server-fqdn>

### Adding a Replica to Extra Large deployments

In Extra Large deployments you must provide the `replica_postgresql_host` parameter set to PE-PostgreSQL host which will be collocated within the same availability group as the new Replica. The `peadm::get_peadm_config` again helps you figure this out. In the **Example** section below, the task has figured out which PE-PostgreSQL server is the Replica database host. You'll find the value at `params.replica_postgresql_host`, which is equal to `pe-psql-6251cd-1.us-west1-b.c.slice-cody.internal`. Reminder, the Replica PE-PostgreSQL server **MUST** be provisioned and deployed prior to initializing a Replica Puppet server.

    bolt plan run peadm::get_peadm_config --targets <primary-server-fqdn> 
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

## Adding Compilers with peadm::add_compiler

Standard deployments are the only architecture of the three which do not have Compilers available upon initial deployment, the lack of them is what differentiates Standard from Large. Architecture has no effect on the process for adding Compilers to a deployment. The [peadm::add_compiler](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/plans/add_compiler.pp) plan functions identical in all three architecture, even if you're adding the 1st or the 100th but some options do change slightly depending.

### Adding Compilers to Standard and Large without disaster recovery

The command invocation is identical when adding compilers to a Standard or Large deployment if disaster recovery (DR) is not enabled and a Replica has not been provisioned. Take note of the values for `avail_group_letter` and `primary_postgresql_host`, in this **no DR**  scenario, the value of these parameter will always be set to **A** and the FQDN of the Primary Puppet server.

    bolt plan run peadm::add_compiler primary_host=<primary-server-fqdn> compiler_host=<new-compiler-fqdn> avail_group_letter=A primary_postgresql_host=<primary-server-fqdn>

### Adding Compilers to Extra Large without disaster recovery

When adding a compiler to an Extra Large deployment in a **no DR** scenario, the only difference is that the `primary_postgresql_host` changes to be the value of the Primary PE-PostgreSQL server as opposed to the Primary Puppet server.

    bolt plan run peadm::add_compiler primary_host=<primary-server-fqdn> compiler_host=<new-compiler-fqdn> avail_group_letter=A primary_postgresql_host=<primary-postgresql-server-fqdn>

### Adding Compilers to Standard and Large when disaster recovery has been enabled

When disaster recovery (DR) is enabled and a Replica provisioned, PEADM creates a second availability group. You must take this into consideration when adding new compilers and ensure you are assigning appropriate values for the group the compiler is targeted for. It is a good idea to keep these two availability groups populated with an equal quantity of compilers. Besides the value of `avail_group_letter` being dependent on which group the new compiler is targeted towards, the value of `primary_postgresql_host` will also vary.

The name of the `primary_postgresql_host` parameter can be confusing, it is **NOT** always equal to the Primary Puppet server or Primary PE-PostgreSQL server, it can also be equal to the Replica Puppet server or Replica PE-PostgreSQL server. It should be set to the server which is a member of the compiler's target availability group. The easiest way to determine this value is to first run the `peadm::get_peadm_config` task and source the value from its output. In the **Example** section the value to use when targeting the **B** group is `pe-server-59ab63-1.us-west1-b.c.slice-cody.internal`. You'll find the value at `role-letter.server.B`.

    bolt plan run peadm::get_peadm_config --targets <primary-server-fqdn> 
    bolt plan run peadm::add_compiler primary_host=<primary-server-fqdn> compiler_host=<new-compiler-fqdn> avail_group_letter=<new-compiler-target-group> primary_postgresql_host=<target-group-server-fqdn>

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

### Adding compilers to Extra Large when disaster recovery has been enabled

Adding a compiler to an Extra Large deployment with disaster recovery (DR) enabled is similar to Standard and Large but the value of `primary_postgresql_host` will not correspond to the Primary or Replica since PuppetDB databases are now hosted external. In the **Example** section the value to use when targeting the **A** group is `pe-psql-65e03f-0.us-west1-a.c.slice-cody.internal`. You'll find the value at `role-letter.postgresql.A`.


    bolt plan run peadm::get_peadm_config --targets <primary-server-fqdn> 
    bolt plan run peadm::add_compiler primary_host=<primary-server-fqdn> compiler_host=<new-compiler-fqdn> avail_group_letter=<new-compiler-target-availability-group> primary_postgresql_host=<target-availability-group-postgresql-fqdn>

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