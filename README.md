# Puppet Enterprise (pe) Administration (adm) Module

This Puppet module contains Bolt plans used to deploy and manage Puppet Enterprise infrastructure. Plans are provided to automate common lifecycle activities in order to increase velocity and reduce the possibility of human error incurred by manually performing these activities.

The peadm module is able to deploy and manage Puppet Enterprise 2019.x Standard, Large, and Extra Large architectures.

#### Table of Contents

1. [Expectations and support](#expectations-and-support)
2. [Overview](#overview)
    * [What peadm affects](#what-peadm-affects)
    * [What peadm does not affect](#what-peadm-does-not-affect)
    * [Requirements](#requirements)
3. [Usage](#usage)
4. [Reference](#reference)
5. [Getting Help](#getting-help)

## Expectations and support

The peadm module is intended to be used only by Puppet Enterprise customers actively working with and being guided by Puppet Customer Success teams—specifically, the Professional Services and Solutions Architecture teams. Independent use is not recommended for production environments without a comprehensive understanding of the peadm module.

The peadm module is a services-led tool, and is **NOT** supported through Puppet Enterprise's standard or premium [support.puppet.com](https://support.puppet.com) service.

As a services-led tool, Puppet Enterprise customers who are advised to start using this tool should get support for it through the following general process.

1. Be introduced to the tool through a services engagement or by their Technical Account Manager (TAM).
2. During Professional Services (PS) engagements, the Puppet PS team will aid and instruct in use of the tool.
3. Outside of PS engagements, use TAM services to request assistance with problems encountered when using the tool, and to inform Puppet Customer Success (CS) teams of planned major maintenance or upgrades for which advisory services are needed.
4. In the absence of a TAM, your Puppet account management team (Account Executive and Solutions Engineer) may be a fallback communication option for requesting assistance, or for informing CS teams of planned major maintenance for which advisory services are needed.

## Overview

The normal usage pattern for peadm is as follows.

1. Users set up a Bolt host from which they can run peadm plans. The Bolt host can be any machine that has ssh access to all of the PE nodes.
2. Users run the `peadm::provision` plan to bootstrap a new PE deployment. Depending on the architecture chosen, peadm may create some node groups in the classifier to set parameters on the built-in `puppet_enterprise` module, tuning it for large or extra large architectures.
3. Users use and operate their PE deployment as normal. The peadm module is not used again until the next upgrade.
4. When it is time to upgrade, users run the `peadm::upgrade` plan from their Bolt host to accelerate and aid in the upgrade process.

### What peadm affects

* The `peadm::provision` plan adds a number of custom OID trusted facts to the certificates of PE infrastructure nodes as it deploys them. These trusted facts are later used by the plans to quickly and correctly identify nodes in particular roles.
* Up to four node groups may be created to help configure `puppet_enterprise` class parameters for PE infrastructure roles. The most notable configuration is the designation of compilers as being either "A" or "B" nodes for availability.

### What peadm does not affect

* The peadm module is not required to exist or be present outside of the point(s) in time it is used to create a new PE deployment, or upgrade an existing deployment. No new Puppet classes or other persistent content not provided out-of-box by PE itself is applied to PE infrastructure nodes by the peadm module.
* Having used the peadm module to provision or to upgrade a PE deployment is not known to affect or curtail the ability to use any normal, documented PE procedures, e.g. failover to a replica, or manual upgrade of a deployment.

### Requirements

* Puppet Enterprise 2019.8.1 or newer (tested with PE 2021.0)
* Bolt 2.27.0 or newer (tested with Bolt 3.5)
* EL 7, EL 8, Ubuntu 18.04, or Ubuntu 20.04
* Classifier Data enabled. This PE feature is enabled by default on new installs, but can be disabled by users if they remove the relevant configuration from their global hiera.yaml file. See the [PE docs](https://puppet.com/docs/pe/latest/config_console.html#task-5039) for more information.

## Usage

Follow the links below to usage instructions for each peadm plan.

* [Provision](documentation/provision.md)
* [Upgrade](documentation/upgrade.md)
* [Convert](documentation/convert.md)
* [Status](documentation/status.md)

## Reference

Additional documentation and information pertaining to various aspects or elements of peadm.

* [PE Architecture Documentation](https://puppet.com/docs/pe/latest/choosing_an_architecture.html)
* [Classification](documentation/classification.md)
* [Architectures](documentation/architectures.md)
* [Testing](documentation/pre_post_checks.md)
* [Docker Based Examples](documentation/docker_examples.md)

## Getting Help

To get help with issues concerning this module, please make use of [issues](https://github.com/puppetlabs/puppetlabs-peadm/issues) in the project on GitHub.
