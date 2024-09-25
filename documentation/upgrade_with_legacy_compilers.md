# Upgrade Puppet Enterprise with legacy compilers

## What is a legacy compiler and a current compiler

As a legacy compiler we refer to a compiler that doesn't have PuppetDB. And a current Compiler is a compiler that has PuppetDB. By default, latest versions of Puppet enterprise comes with compilers that have PuppetDB.If your primary server and compilers are connected with high-latency links or congested network segments, you might experience better PuppetDB performance with legacy compilers.

## Who is this documentation for

For those users that have installed Puppet Enterprise with puppetlabs-peadm prior version 3.25 and manually converted their existing complilers (all of the or at least 1) to legacy compilers.

## Who is this documentation not for

For those users that have installed Puppet Enterprise with PEADM with 3.25 version or later, there is no need to follow this documentation. The install process will automatically have created the necessary configurations for you and you can use the `peadm::convert_compiler_to_legacy` plan if you need a legacy compiler. example:

```shell
bolt plan run peadm::convert_compiler_to_legacy legacy_hosts=compiler1.example.com,compiler2.example.com primary_host=primary.example.com
```

## How to upgrade Puppet Enterprise with legacy compilers

### 1. Revert changes to the legacy compilers nodes

Usually users pin the nodes in the Pe Master Node Group and then manually removing PuppetDB from compilers nodes. To revert this changes go to your Puppet Enterprise console and unpin the compilers nodes from the Group.

### 2. Upgrade Puppet Enterprise

You can proceed with the upgrade of Puppet Enterprise as usual using the puppetlabs-peadm module 3.25 or later and pass legacy compilers to the upgrade plan.
