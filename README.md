# Puppet Enterprise Administration Module (PEADM)

PEADM helps you install, upgrade, and manage Puppet Enterprise (PE). It uses Bolt plans (sets of steps) that the Bolt Application runs on your servers.

PEADM supports Standard, Large, and Extra Large setups. The examples below show the minimum setup for one primary server, which manages the PE installation.

## Table of contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Project Setup](#project-setup)
  - [Project Inventory](#project-inventory)
  - [Optional - Use an SSH public/private key](#optional---use-an-ssh-publicprivate-key)
  - [Optional - Encrypt the passwords](#optional---encrypt-the-passwords)
  - [Check the connection](#check-the-connection)
  - [Using peadm::install and peadm::upgrade](#using-peadminstall-and-peadmupgrade)
    - [Install](#install)
    - [Upgrade](#upgrade)
  - [Plan Parameters](#plan-parameters)
- [More guides](#more-guides)
  - [Add Additional Puppet Infrastructure](#add-additional-puppet-infrastructure)
- [Support and Getting Help](#support-and-getting-help)
- [License](#license)

## Overview

PEADM sets up PE servers and groups them by their jobs. It adds labels to their Puppet certificates so it can identify each server later. Larger setups can have extra servers to handle Puppet requests, store data, or take over after a failure.

Once setup is done, PE runs on its own. Run PEADM again when you need to upgrade or add servers. You can still use the normal PE tools and procedures.

PEADM has other plans for tasks such as adding servers, making backups, and restoring PE. Find them in the [Plans section of the reference guide](REFERENCE.md#plans).

## Requirements

- Works with PE 2019.8.1 or newer. Upgrade older PE versions before you convert them to PEADM management.
- Install [Bolt](https://help.puppet.com/bolt/current/topics/bolt_installing.htm) version 3.17.0 or newer on the computer that will run the plans.
- Use a server operating system supported by the PE version you plan to install.
- Have SSH access to each server and permission to run commands as `root` through sudo or changing your privileges.
- For a new install, start with servers that do not have Puppet installed.

If you are converting an existing PE setup, allow changes to classifier configuration data first. These are settings for PE node groups. See the [conversion guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md) for the full steps.

## Usage

Follow these steps for a basic project and a single-server inventory. An inventory is the file that tells Bolt which servers to connect to and how to log in. For larger setups, use the [installation guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md).

### Project Setup

On the computer where you installed Bolt, create a project and add PEADM:

```sh
mkdir peadm_project
cd peadm_project
bolt project init peadm_project --modules puppetlabs-peadm
```

Run the rest of the commands from this folder.

### Project Inventory

Save this file as `inventory.yaml` in your project folder. Replace the server name, user, and passwords with your own values:

A basic example:
```yaml
---
targets:
  - name: primary.example.com
config:
  transport: ssh
  ssh:
    user: my_admin_user
    password: "REPLACE_WITH_SSH_PASSWORD"
    run-as: root
    sudo-password: "REPLACE_WITH_SUDO_PASSWORD"
```

Bolt logs in as `my_admin_user`, then uses sudo to run commands as `root`. The user must have sudo access. Bolt must also trust the server's SSH host key before it connects.

The two password fields have different jobs:

- `password` is for the SSH login.
- `sudo-password` is the password sudo asks for. This is usually the login user's password, though your server may use a different rule.

Neither field is the PE console password. You will set that in `params.json` when you install PE.

See [Bolt's sudo guide](https://help.puppet.com/bolt/current/topics/privilege_escalation.htm) for more privilege options.

### Optional - Use an SSH public/private key

You can also use an SSH public/private key pair to connect to servers with PEADM. Set up the public key for the login user on each server, and set Bolt's `private-key` option to the private key file on your Bolt computer. See [Bolt's SSH key settings](https://help.puppet.com/bolt/current/topics/bolt_transports_reference.htm) for details. You may still need a `sudo-password` to run commands as root.

### Optional - Encrypt the passwords

You can use Bolt's [PKCS7 plugin](https://forge.puppet.com/modules/puppetlabs/pkcs7) to store encrypted passwords in the inventory. Encryption uses a public key to protect a value and a private key to read it again.

Update `bolt-project.yaml` to match this complete example. Keep any other modules your project already uses:

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

Create the keys once. Then run one command for each password you want to encrypt:

```sh
mkdir -p keys
bolt secret createkeys --plugin pkcs7
bolt secret encrypt 'REPLACE_WITH_SSH_PASSWORD' --plugin pkcs7
bolt secret encrypt 'REPLACE_WITH_SUDO_PASSWORD' --plugin pkcs7
```

Each encryption command returns a value that starts with `ENC[PKCS7,`. Copy each full value into the matching field below. Replace your `inventory.yaml` with this complete file, using your server name and login user:

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

Bolt uses the private key to read the passwords when it needs them.

> **Warning:** Before you commit this project to GitHub or another Git repository, move `keys/private_key.pkcs7.pem` out of the project and put it in a secret store. Add the key's path to `.gitignore` to help keep it out of Git. When you run Bolt, get the key from the secret store and place it in a protected folder outside the project. Change `plugins.pkcs7.private_key` in `bolt-project.yaml` to point to that file. If you already committed the key, deleting it does not erase it from Git history. Create a new key pair and encrypt the passwords again.

A real password typed into an encryption command may stay in your shell history. See the [Bolt secret commands](https://help.puppet.com/bolt/current/topics/bolt_command_reference.htm) and [plugin guide](https://help.puppet.com/bolt/current/topics/using_plugins.htm) for more details.

### Check the connection

Run this command before you run a plan:

```sh
bolt command run 'whoami' --targets primary.example.com
```

It should return `root`. If it does not, check the SSH and sudo settings in your inventory.

### Using peadm::install and peadm::upgrade

Choose the plan you need below. Save its settings in `params.json` in your project folder. The `primary_host` must match the server name in your inventory.

#### Install

To install a new Standard setup, use this `params.json`. Replace the server name and choose a password for the PE console admin account:

```json
{
  "primary_host": "primary.example.com",
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD",
  "version": "2025.12.0"
}
```

Run the install plan:

```sh
bolt plan run peadm::install --params @params.json
```

This example installs PE 2025.12.0. For other server layouts and install options, see the [install guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/install.md).

#### Upgrade

To upgrade a Standard setup that PEADM already manages, use this `params.json`:

```json
{
  "primary_host": "primary.example.com",
  "version": "2025.12.0"
}
```

Run the upgrade plan:

```sh
bolt plan run peadm::upgrade --params @params.json
```

This example upgrades to PE 2025.12.0. Check that your current PE version can upgrade to it before you start. For larger setups, include the existing compiler, replica, and separate database servers. See the [upgrade guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/upgrade.md) for the required checks and settings.

### Plan Parameters

Each plan accepts its own set of settings, called parameters. Use the file for the plan you are running; a full install file may include settings that another plan does not accept.

The [parameters guide](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/params.md) lists these settings, with minimal and full examples for each plan. After an install, see [Remove installation console passwords](documentation/remove_secrets.md) to clean the console password from local `params.json` and the primary's temporary `/tmp/pe.conf`. That cleanup leaves the running configuration and license files in place.

## More guides

- [Plan and API reference](REFERENCE.md)
- [Convert an existing PE setup](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert.md)
- [Check PE status](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/status.md)
- [Choose a server layout](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/architectures.md)
- [How PEADM groups servers](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/classification.md)
- [Recover after a failure](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/recovery/recovery.md)
- [Test before and after changes](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/pre_post_checks.md)
- [Docker examples](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/docker_examples.md)
- [Release process](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/release_process.md)

### Guides for expanding your PE setup
- [Overview on expanding your PE setup](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/expanding.md)
- [Add compilers](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/add_compilers.md)
- [Convert compilers to legacy compilers](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/convert_compiler_to_legacy.md)
- [Add disaster recovery](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/add_replica.md)
- [Add stand-alone database servers](https://github.com/puppetlabs/puppetlabs-peadm/blob/main/documentation/expanding.md#adding-external-databases-with-peadmadd_database)

## Support and Getting Help

PEADM is a supported PE module. PE customers with standard or premium support can [contact the Support team](https://portal.perforce.com/s/topic/0TO4X000000DbNgWAK/puppet) or their Technical Account Manager for help, including during an outage.

To report a bug, [open a GitHub issue](https://github.com/puppetlabs/puppetlabs-peadm/issues).

## License

PEADM uses the Apache 2.0 license. Some open source tools it depends on use other licenses, such as AGPL, GPL 2.0, and MIT.
