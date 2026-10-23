# Puppet Enterprise Administration Module (PEADM)

The Puppet Enterprise Administration Module (PEADM) contains a set of Bolt plans designed for deploying and managing Puppet Enterprise (PE) infrastructure. These plans automate key PE lifecycle activities to accelerate deployment and reduce the risk of human error.

You can use PEADM to deploy and manage PE installations for standard, large, and extra-large architectures.

**Important**: PEADM is compatible with PE 2019.8.1 and later versions. If your PE version is older than 2019.8.1 and you want to use PEADM, you must upgrade PE before converting your installation to a PEADM-managed installation.

#### Table of contents

- [Overview](#overview)
  - [What PEADM affects](#what-peadm-affects)
  - [What PEADM does not affect](#what-peadm-does-not-affect)
  - [Requirements](#requirements)
- [Usage](#usage)
  - [Setup](#setup)
    - [Project Setup](#project-setup)
    - [Project Inventory](#project-inventory)
  - [Using peadm::install and peadm::upgrade](#using-peadminstall-and-peadmupgrade)
    - [Install](#install)
    - [Upgrade](#upgrade)
  - [Plan Parameters](#plan-parameters)
- [Reference](#reference)
- [Support and Getting Help](#support-and-getting-help)
- [License](#license)

## Overview

PEADM provides plans to install, upgrade and manage Puppet Enterprise infrastructure. Start with [Usage](#usage) to create a Bolt project and inventory.

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

- PEADM is compatible with Puppet Enterprise 2019.8.1 and newer versions.
- PEADM requires [Bolt](https://help.puppet.com/bolt/current/topics/bolt_installing.htm) version 3.17.0 or newer and works on operating systems supported by Bolt.
  **Note:** You can use PEADM to install Puppet Enterprise (PE) onto any operating system platform that is supported by the specific PE version you want to install. To review operating system platforms supported by specific PE versions, refer to the PE documentation.
- To successfully convert your current PE installation to a PEADM-managed installation, ensure that the PE setting for editing classifier configuration data is enabled. This setting is enabled by default on new PE installations, but it could be disabled if the relevant configuration was removed from your global hiera.yaml file. See the [PE docs](https://help.puppet.com/pe/current/topics/config_console.htm) for more information.

## Usage

### Setup

This is the minimum setup to get started with PEADM and the minimum inventory for a single-primary Standard deployment. For complete requirements, other architectures and installation options, see the [PEADM installation guide on GitHub](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md).

#### Project Setup

Install Puppet Bolt on the machine from which you will run the plans. Then create a project with the PEADM module:

```sh
mkdir peadm_project
cd peadm_project
bolt project init peadm_project --modules puppetlabs-peadm
```

Run the remaining commands from this project directory. Create `inventory.yaml` as shown below, then create the `params.json` for [install or upgrade](#using-peadminstall-and-peadmupgrade). See the [GitHub installation instructions](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md#usage) for more project setup details.

#### Project Inventory

Save this minimum inventory as `inventory.yaml` in the project directory. Replace the hostname, login user, SSH password and sudo password with your target's connection details:

```yaml
---
targets:
  - name: primary.example.com
config:
  transport: ssh
  ssh:
    user: my_system_admin_user
    password: "REPLACE_WITH_SSH_PASSWORD"
    run-as: root
    sudo-password: "REPLACE_WITH_SUDO_PASSWORD"
```

Bolt connects over SSH as `my_system_admin_user`, then uses `run-as: root` to execute commands with sudo. The login user must have sudo permission on the target, and its SSH host key must already be trusted by the Bolt controller. `password` authenticates the SSH login; `sudo-password` supplies the password requested by sudo when switching to root (normally the login user's password, depending on sudo policy). Configure these separately; neither is the PE console password supplied in `params.json`. See [Bolt privilege escalation](https://help.puppet.com/bolt/current/topics/privilege_escalation.htm) for details.

To encrypt both passwords with Bolt's [PKCS7 plugin](https://forge.puppet.com/modules/puppetlabs/pkcs7), add its configuration to `bolt-project.yaml`. This is the complete project file for this example, including the PEADM module:

```yaml
---
name: peadm_project
modules:
  - name: puppetlabs-peadm
plugins:
  pkcs7:
    keysize: 2048
    public_key: keys/public_key.pkcs7.pem
    private_key: keys/private_key.pkcs7.pem
```

From the project directory, create the keys once, then encrypt the SSH and sudo passwords separately:

```sh
mkdir -p keys
bolt secret createkeys --plugin pkcs7
bolt secret encrypt 'REPLACE_WITH_SSH_PASSWORD' --plugin pkcs7
bolt secret encrypt 'REPLACE_WITH_SUDO_PASSWORD' --plugin pkcs7
```

Copy each complete `ENC[PKCS7,...]` value returned by the encryption commands into its corresponding field in `inventory.yaml`. This is the complete encrypted inventory:

```yaml
---
targets:
  - name: primary.example.com
config:
  transport: ssh
  ssh:
    user: peadmin
    password:
      _plugin: pkcs7
      encrypted_value: "ENC[PKCS7,REPLACE_WITH_ENCRYPTED_SSH_PASSWORD]"
    run-as: root
    sudo-password:
      _plugin: pkcs7
      encrypted_value: "ENC[PKCS7,REPLACE_WITH_ENCRYPTED_SUDO_PASSWORD]"
```

Bolt decrypts the passwords when needed.

> **Warning:** If you committing this Bolt project to a company/personal repository, remove `keys/private_key.pkcs7.pem` from the project and store it in a secret store. Exclude the private key from Git with `.gitignore`. Retrieve it to a protected location outside the repository when running Bolt, and update `plugins.pkcs7.private_key` in `bolt-project.yaml` to that location. If the key was already committed, removing the file does not remove it from Git history; rotate the key and re-encrypt the passwords.

 These commands use a placeholder password; substituting a real password directly on the command line can leave it in shell history. See the [Bolt secret command reference](https://help.puppet.com/bolt/current/topics/bolt_command_reference.htm) and [plugin configuration guide](https://help.puppet.com/bolt/current/topics/using_plugins.htm) for more details.

Check the connection before running a plan:

```sh
bolt command run 'whoami' --targets primary.example.com
```

The command should return `root`. Use `primary.example.com` as the `primary_host` in your `params.json`. Add targets for compilers, replicas or separate PostgreSQL hosts when your architecture requires them. For inventory examples and target-name mapping, see the [PEADM installation guide on GitHub](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md#usage) and [PEADM parameter guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/params.md)

### Using peadm::install and peadm::upgrade

Run these plans with Bolt from a project containing the `puppetlabs-peadm` module and an `inventory.yaml` with connection details for your PE hosts. Target names in `params.json` must match your inventory. See the [installation guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md) for project and inventory setup.

#### Install

To install a new Standard deployment, save this basic `params.json`, replacing the hostname and password:

```json
{
  "primary_host": "primary.example.com",
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD",
  "version": "2025.12.0"
}
```

Run:

```sh
bolt plan run peadm::install --params @params.json
```

The target must not already have Puppet installed. The version above is an example; select the supported PE version you intend to install. See the [install guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md) for different architectures, prerequisites, and media options.

#### Upgrade

To upgrade an existing PEADM-managed Standard deployment, save this basic `params.json`, replacing the hostname and setting the destination version:

```json
{
  "primary_host": "primary.example.com",
  "version": "2025.12.0"
}
```

Run:

```sh
bolt plan run peadm::upgrade --params @params.json
```

Choose a supported destination version appropriate for your current installation. For larger deployments or disaster recovery, include the existing compiler, replica and separate PostgreSQL hosts as applicable. See the [upgrade guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/upgrade.md) for prerequisites and upgrade options.

The [parameters guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/params.md) documents each plan's accepted parameters with minimal and full `params.json` examples. Install and upgrade accept different arguments; prepare the file for the plan you are running.

For more detailed plan instructions, see the documentation on GitHub:

- [Install](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md)
- [Upgrade](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/upgrade.md)
- [Convert](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md)
- [Status](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/status.md)
- [Remove installation console passwords](documentation/remove_secrets.md)

### Plan Parameters

For individual parameters and minimal and full `params.json` examples, see the [parameters guide on GitHub](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/params.md).

## Reference

To understand which architecture is right for you, review the [PE architectures](https://help.puppet.com/pe/current/topics/supported_architectures.htm) documentation.

To learn more about the PEADM module and its uses, see the following PEADM docs:

- [Recovery procedures](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/recovery/recovery.md)
- [Architectures](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/architectures.md)
- [Expanding deployment](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/expanding.md)
- [Classification](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/classification.md)
- [Testing](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/pre_post_checks.md)
- [Docker based examples](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/docker_examples.md)
- [Release process](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/release_process.md)

## Support and Getting Help

PEADM is a supported PE module. If you are a PE customer with the standard or premium support service, you can [contact the Support team](https://portal.perforce.com/s/topic/0TO4X000000DbNgWAK/puppet) or your Technical Account Manager for assistance.

- If you find a bug, an optional [GitHub issue](https://github.com/puppetlabs/puppetlabs-peadm/issues) exists. Feel free to create a new report.
- For PE customers using PEADM and experiencing outages or other issues, [contact the Support team](https://portal.perforce.com/s/topic/0TO4X000000DbNgWAK/puppet).

## License

This codebase is licensed under Apache 2.0. However, the open source dependencies included in this codebase might be subject to other software licenses such as AGPL, GPL2.0, and MIT.
