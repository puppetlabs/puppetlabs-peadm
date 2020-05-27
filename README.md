# Puppet Enterprise (pe) Administration (adm) Module

This Puppet module contains Bolt plans used to deploy and manage Puppet Enterprise infrastructure. Plans are provided to automate common lifecycle activities, in order to increase velocity and reduce the possibility of human error incurred by manually performing these activities.

The peadm module is able to deploy and manage Puppet Enterprise 2019.x Standard, Large, and Extra Large architectures.

## Expectations

The peadm module is intended to be used only by Puppet Enterprise customers actively working with and being guided by Puppet Customer Success teams—specifically, the Support team and the Solutions Architecture team. Independent use is not recommended for production environments.

## Documentation

See this README file and any documents in the [documentation](documentation) directory.

Plans:

* [Provision](documentation/provision.md)
* [Upgrade](documentation/upgrade.md)
* [Convert](documentation/convert.md)
* [Status](documentation/status.md)

Reference:

* [PE Architecture Documentation](https://puppet.com/docs/pe/latest/choosing_an_architecture.html)
* [Classification](documentation/classification.md)
* [Architectures](documentation/architectures.md)
* [Testing](documentation/pre_post_checks.md)
* [Docker Based Examples](documentation/docker_examples.md)

## Requirements

Normally, if you are able to use peadm to set up an infrastructure and Puppet agent runs are all working, chances are you met all the requirements and don't have to worry. Sometimes Some notable requirements are highlighted below which may accidentally be adjusted by users, but which architectures deployed by this module rely on. These configuration requirements need to be maintained for the infrastructure to operate correctly.

* Classifier Data needs to be enabled. This feature is enabled by default on new installs, but can be disabled by users if they remove the relevant configuration from their global hiera.yaml file. See the [PE docs](https://puppet.com/docs/pe/latest/config_console.html#task-5039) for more information.

## Getting Help

To get help with issues concerning this module, please make use of [issues](https://github.com/puppetlabs/puppetlabs-peadm/issues) in the project on GitHub.
