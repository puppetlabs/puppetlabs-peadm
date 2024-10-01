# Convert infrastructure for use with the PEADM module

The peadm::convert plan can be used to adopt manually deployed infrastructure for use with PEADM or to adopt infrastructure deployed with an older version of peadm.

>To understand what classifications PEADM adds to your infrastructure, please see [here](classification.md).

## Convert an Existing Deployment

Prepare to run the plan against all servers in the PE infrastructure, using a params.json file such as this one:

```json
{
  "primary_host": "pe-xl-core-0.lab1.puppet.vm",
  "replica_host": "pe-xl-core-1.lab1.puppet.vm",
  "compiler_hosts": [
    "pe-xl-compiler-0.lab1.puppet.vm",
    "pe-xl-compiler-1.lab1.puppet.vm"
  ],
  "legacy_compilers": [
    "pe-xl-legacy-compiler-0.lab1.puppet.vm",
    "pe-xl-legacy-compiler-1.lab1.puppet.vm"
  ],
  "compiler_pool_address": "puppet.lab1.puppet.vm"
}
```

See the [install](install.md#reference-architectures) documentation for a list of supported architectures. Note that for convert, _all infrastructure being converted must already be functional_; you cannot use convert to add new systems to the infrastructure, nor can you use it to change your architecture.

```
bolt plan run peadm::convert --params @params.json
```

## Retry or resume plan

This plan is broken down into steps. Normally, the plan runs through all the steps from start to finish. The name of each step is displayed during the plan run, as the step begins.

The `begin_at_step` parameter can be used to facilitate re-running this plan after a failed attempt, skipping past any steps that were already completed successfully on the first try and picking up again at the step specified. The step name to resume can be read from the previous run logs. A full list of available values for this parameter can be viewed by running `bolt plan show peadm::convert`.

## Convert compilers to legacy

### Puppet Enterprise installed with puppetlabs-peadm version 3.25 or later

To convert compilers to legacy compilers use the `peadm::convert_compiler_to_legacy` plan. This plan will create the needed Node group and Classifier rules to make compilers legacy. Also will add certificate extensions to those nodes.

```shell
bolt plan run peadm::convert_compiler_to_legacy legacy_hosts=compiler1.example.com,compiler2.example.com primary_host=primary.example.com
```

### Puppet Enterprise installed with puppetlabs-peadm version prior to 3.25

Follow Steps 1 to 3 in the [Upgrade Puppet Enterprise with legacy compilers](upgrade_with_legacy_compilers.md) documentation.
