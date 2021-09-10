# Pre and post flight testing

The module as been updated to be supported by Puppetlabs [Litmus](https://github.com/puppetlabs/puppet_litmus/wiki/Overview-of-Litmus#provision).

The module [ServerSpec](https://serverspec.org/) tests for the Bolt Tasks and Plans provided can be used agains a deployment infrastrcuture run as Post flight checks if desired.

Additionally some stand a lone preflight checks will be added presently.

## Setup

The module as been converted to Litmus as the directions found at https://puppetlabs.github.io/litmus/Converting-modules-to-use-Litmus.html that means the following files have been added.
``` shell
\.
├── spec
│   │   
│   ├── spec_helper_acceptance_local.rb
│   ├── spec_helper.rb
│   └── spec_helper_acceptance.rb
└── provision.yaml
```

An update to .gitignore for the Litmus generated `.rerun.json` has also been made via `.sync.yaml` PDK functionality. 

## Usage

Litmus can provision local testing via provisioning and generation of a Bolt inventory.yaml, see https://puppetlabs.github.io/litmus/Running-acceptance-tests.html for an example.

### Inventory 
when testing locally with Vagrant or VMpooler you can use the `litmus:provision` rake task to generate an inventory.yml.

You will normally need to create an `inventory.yaml` for your target puppet infrastructure, and you may want to group your puppet infrastructure related to the Puppet Console classification node groups. A possible example `inventory.yaml` is illustrated.

Note that if you are using Litmus against a host once the agent is installed (not for pre deployment checks of peadm) you will want to add `features: ['puppet-agent']` to your inventory.yaml this resolves several error messages otherwise encountered. 

``` yaml

---
groups:
- name: peserver
  nodes:
  - primary.puppet.example.net
  features: ['puppet-agent']
  config:
    transport: ssh
    ssh:
      host-key-check: false
      user: centos
      run-as: root
      private-key: "~/.ssh/example.pem"
- name: "compilers"
  nodes:
  - compiler00.puppet.example.net
  features: ['puppet-agent']
  config:
    transport: ssh
    ssh:
      host-key-check: false
      user: centos
      run-as: root
      private-key: "~/.ssh/example.pem"
- name: ha
  nodes:
  - ha-primary.puppet.example.net
  features: ['puppet-agent']  
  config:
    transport: ssh
    ssh:
      host-key-check: false
      user: centos
      run-as: root
      private-key: "~/.ssh/example.pem"
- name: windowsagents
  nodes:
  - win0.example.net
  features: ['puppet-agent']
  config:
    transport: winrm
    winrm:
      user: domainadminaccount
      password: "@example"
      ssl: false
- name: linuxagents
  nodes:
  - nix0.example.net
  features: ['puppet-agent']
  config:
    transport: ssh
    ssh:
      host-key-check: false
      user: centos
      run-as: root
      private-key: "~/.ssh/example.pem"
```

### Tests and Checks

One you have the module deployed any Pre or Post deployment checks can be developed as standard ServerSpec tests and orchestrated using Bolt and Litmus. 

A default check exists in `peadm_spec.rb`, note the test is constrained using the os[:family] fact. The example test simply prints it's context and will not fail.

``` shell
spec
├── acceptance
    └── peadm_spec.rb


require 'spec_helper_acceptance'
# @summary: default test does nothing
def test_peadm()
  
    #return unless os[:family] != 'windows'
    return unless os[:family] != 'Darwin'
end

describe 'default' do
  context 'example acceptance do nothing' do
    it do
        test_peadm()
    end
  end
end

```

For running the tests review the standard usage of Litmusfor installing and running tests https://puppetlabs.github.io/litmus/Running-acceptance-tests.html#6-run-the-motd-acceptance-tests
remember we are doing these actions from within the context of the PDK `pdk bundle exec rake ` has several sub commands. 

```shell
rake litmus:acceptance:<target || nodes> 
# Run serverspec against targets:name 
rake litmus:acceptance:localhost                                                # Run serverspec against localhost, USE WITH CAUTION, this action can be potentially dangerous
rake litmus:acceptance:parallel                                                 # Run tests in parallel against all machines in the inventory file
rake litmus:acceptance:serial                                                   # Run tests in serial against all machines in the inventory file
rake litmus:install_agent[collection,target_node_name]                          # install puppet agent, [:collection, :target_node_name]
rake litmus:install_module[target_node_name]                                    # install_module - build and install module
rake litmus:install_modules_from_directory[source,target_node_name]             # install_module - build and install module
rake litmus:metadata                                                            # print all supported OSes from metadata
rake litmus:provision[provisioner,platform,inventory_vars]                      # provision container/VM - abs/docker/vagrant/vmpooler eg 'bundle exec rake 'litmus:provision[vmpooler, ubuntu-160...
rake litmus:provision_install[key,collection]                                   # provision_install - provision a list of machines, install an agent, and the module
rake litmus:provision_list[key]                                                 # provision list of machines from provision.yaml file
rake litmus:reinstall_module[target_node_name]                                  # reinstall_module - reinstall module
rake litmus:tear_down[target]                                                   # tear-down - decommission machines
rake litmus:uninstall_module[target_node_name,module_name]                      # uninstall_module - uninstall module
```


