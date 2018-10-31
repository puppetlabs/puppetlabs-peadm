# Puppet Enterprise Extra Large

This Puppet module contains profile classes used to deploy an at-scale Puppet Enterprise architecture.

It SHOULD contain instructions for how to set that all up, too. Right now it doesn't. Big To-do.

Note pending more detailed instructions:

* This deployment depends on and assumes the use of trusted facts. Specifically, `pp_role` and `pp_environment`.
* This deployment assumes that at least for PE infrastructure nodes, Puppet certnames are correct, resolvable FQDNs.
* This deployment assumes the control repository to manage PE is independent of the normal "customer" control-repo.

## Documentation

See this README file and any documents in the [documentation](documentation) directory.

## Architecture

![architecture](documentation/images/architecture.png)

## Installation

These are just sketched out instructions right now. It's likely there are big gaps still.

### Prepare the Control Repositories

You'll need two control repositories configured. One dedicated to managing Puppet Enterprise nodes (consider it kinda like an appliance), and another for your regular Puppet code used to manage your infrastructure.

### Installing the Master

1. Download and extract the Puppet Enterprise installer
2. Place the csr\_attributes.yaml file from installer/master in /etc/puppetlabs/puppet/csr\_attributes.yaml
3. Place the pe.conf file from installer/master in the working directory, and edit it to fill in required values
4. Run the installer, passing the appropriate flags to use the prepared pe.conf file
5. Set up the ssh private keys needed to access the configured control repositories
6. For each environment configured (however many you want to initially deploy), run e.g.

        puppet code deploy production --wait
        puppet code deploy pe_production --wait

7. Using the same list of environments deployed above, run e.g.

        puppet apply --environment pe_production --exec '
          class { "pe_xl::node_manager":
            environments => ["production", "pe_production"],
          }
        '

5. Perform the PuppetDB Database installation (described below)
6. Run `puppet agent -t`

### Installing the PuppetDB Database

1. Download and extract the Puppet Enterprise installer
2. Place the csr\_attributes.yaml file from installer/puppetdb-database in /etc/puppetlabs/puppet/csr\_attributes.yaml
3. Place the pe.conf file from installer/puppetdb-database in the working directory, and edit it to fill in required values
4. Run the installer, passing the appropriate flags to use the prepared pe.conf file
5. Finish the Master installation (described above)
6. Run `puppet agent -t`

### Installing a Compiler

```
curl -k https://master.example.com:8140/packages/current/install.bash | sudo bash -s \
  main:certname=<certname> \
  extension_requests:pp_role="pe_xl::compiler" \
  extension_requests:pp_environment="pe_production"
```
