# Puppet Enterprise Administration Module (PEADM)

The Puppet Enterprise Administration Module (PEADM) contains a set of Bolt plans designed for deploying and managing Puppet Enterprise (PE) infrastructure. These plans automate key PE lifecycle activities to accelerate deployment and reduce the risk of human error.

You can use PEADM to deploy and manage PE installations for standard, large, and extra-large architectures.

**Important**: PEADM is compatible with PE 2019.8.1 and later versions. If your PE version is older than 2019.8.1 and you want to use PEADM, you must upgrade PE before converting your installation to a PEADM-managed installation.

#### Table of contents

- [Puppet Enterprise Administration Module (PEADM)](#puppet-enterprise-pe-administration-adm-module)
  - [Table of contents](#table-of-contents)
  - [Support](#support)
  - [Overview](#overview)
    - [What PEADM affects](#what-peadm-affects)
    - [What PEADM does not affect](#what-peadm-does-not-affect)
    - [Requirements](#requirements)
  - [Usage](#usage)
  - [Reference](#reference)
  - [Getting help](#getting-help)
  - [License](#license)

## Support

PEADM is a supported PE module. If you are a PE customer with the standard or premium support service, you can contact [Support](https://portal.perforce.com/s/topic/0TO4X000000DbNgWAK/puppet) or your Technical Account Manager for assistance.

## Overview

This is the standard workflow for installing PEADM.

1. [Install Bolt](https://www.puppet.com/docs/bolt/latest/bolt_installing) on a jump host.
2. To create a Bolt project that includes the PEADM module, run:</br>`mkdir <YOUR_PROJECT> && cd <YOUR_PROJECT> && bolt project init <YOUR_PROJECT> --modules puppetlabs-peadm`
3. In the Bolt project directory, update the `inventory.yaml` file with connection information for the servers you plan to use for hosting PE infrastructure. For example:

```yaml
---
groups:
  - name: puppet-enterprise-nodes
    config:
      transport: ssh
      ssh:
        host-key-check: false
        user: centos
        run-as: root
    targets:
      - pe-xl-core-0.lab1.puppet.vm
      - pe-xl-core-1.lab1.puppet.vm
      - pe-xl-core-2.lab1.puppet.vm
      - pe-xl-core-3.lab1.puppet.vm
      - name: pe-xl-compiler-0.lab1.puppet.vm
        uri: 10.234.6.45
      - name: pe-xl-compiler-1.lab1.puppet.vm
        uri: 10.234.14.131
```

### What PEADM affects

- The `peadm::install` plan adds a number of custom original identifier (OID) trusted facts to the certificates of deployed PE infrastructure nodes. These trusted facts are used by PEADM plans to identify nodes that host PE infrastructure components.
- Depending on the scale of your architecture, up to four node groups may be created to configure `puppet_enterprise` class parameters for the following PE infrastructure components:
  - The primary server
  - The primary server replica
  - PostgreSQL nodes (database servers)
  - Compilers (compiler hosts are designated as belonging to availability group A or B)

### What PEADM does not affect

- PEADM does not impact regular PE operations. After using it to deploy a new PE installation or upgrade an existing one, PEADM is not required until you want to use it to upgrade PE or expand your installation.
- Using PEADM to install PE or upgrade PE does not prevent you from using documented PE procedures such as setting up disaster recovery or performing a manual upgrade.

### Requirements

- PEADM is compatible with Puppet Enterprise 2019.8.1 or newer versions.
- PEADM requires [Bolt](https://www.puppet.com/docs/bolt/latest/bolt_installing) version 3.17.0 or newer and works on operating systems supported by Bolt.  
  **Note:** You can use PEADM to install Puppet Enterprise (PE) onto any operating system platform that is supported by the specific PE version you want to install. To review operating system platforms supported by specific PE versions, refer to the PE documentation.
- To successfully convert your current PE installation to a PEADM-managed installation, ensure that the PE setting for editing classifier configuration data is enabled. This setting is enabled by default on new PE installations, but it could be disabled if the relevant configuration was removed from your global hiera.yaml file. See the [PE docs](https://www.puppet.com/docs/pe/latest/config_console.html#enable_console_configuration_data) for more information.

## Usage

For instructions on using PEADM plans, see the following PEADM docs:

- [Install](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md)
- [Upgrade](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/upgrade.md)
- [Convert](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md)
- [Status](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/status.md)

## Reference

To understand which architecture is right for you, see the following information on the Puppet documentation site:

- [PE architectures](https://puppet.com/docs/pe/latest/choosing_an_architecture.html)
- [PE multi-region reference architectures](https://puppet.com/docs/patterns-and-tactics/latest/reference-architectures/pe-multi-region-reference-architectures.html)

To learn more about the PEADM module and its uses, see the following PEADM docs:

- [Recovery procedures](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/recovery.md)
- [Architectures](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/architectures.md)
- [Expanding deployment](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/expanding.md)
- [Classification](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/classification.md)
- [Testing](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/pre_post_checks.md)
- [Docker based examples](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/docker_examples.md)
- [Release process](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/release_process.md)

## Getting help

- If you find a bug, you can [create a GitHub issue](https://github.com/puppetlabs/puppetlabs-peadm/issues).
- For PE customers using PEADM and experiencing outages or other issues, [contact the Support team](https://portal.perforce.com/s/topic/0TO4X000000DbNgWAK/puppet).

## License

This codebase is licensed under Apache 2.0. However, the open source dependencies included in this codebase might be subject to other software licenses such as AGPL, GPL2.0, and MIT.
