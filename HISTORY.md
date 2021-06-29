## 2.5.0
### Summary

### Changes

- Require WhatsARanjit-node\_manager >= 0.7.5
- Require puppetlabs-stdlib >= 6.5.0

### Improvements

- Support PE 2021.0
- Handle exit code 11 from replica upgrade task gracefully. Code 11 means "PuppetDB sync in progress but not yet complete"
- Further remediate the bug fixed in 2.4.2, by ensuring that all peadm-managed node groups preserve existing data or class parameters not explicitly being managed
- Switch dependency enumeration from in-project Puppetfile to bolt-project.yaml modules setting

## 2.4.5
### Summary

Bugfix release

### Bugfixes

* Fix an issue in the convert plan incorrectly disallowing conversion of deployments newer than 2019.7.0.
* Fix a problem with the Peadm::SingleTargetSpec type alias.
* Fix peadm::puppet\_runonce to correctly return a failure if the Puppet agent run had resource failures.

## 2.4.4
### Summary

Support PE 2019.8.4 and newer 2019.8.z releases

### Improvements

- Validation should Permit installing or upgrading to any PE 2019.8.z release

## 2.4.3
### Summary

Support PE 2019.8.3

### Improvements

- Support installing or upgrading to PE 2019.8.3

## 2.4.2
### Summary

Bugfix release

### Bugfixes

- Previously, on upgrade, peadm could overwrite user configuration data on the PE Master group because it overwrote the entire configuration data value. This release modifies the peadm::setup::node\_manager desired state configuration to merge required configuration into any existing configuration when configuring data on the PE Master node group.

## 2.4.1
### Summary

Bugfix release

### Bugfixes

- Previously, on upgrade, peadm did not ensure that PostgreSQL servers' pe.conf file contained the critical keys that inform the installer that the system is a stand-alone database. The peadm::upgrade plan now ensures the critical keys are correct as part of the upgrade preparation.
- When upgrading a DR replica to PE 2019.8.0 or 2019.8.1, there is an installer bug that causes the upgrade to fail due to how `puppetdb delete-reports` performs in this configuration. This release works around the problem by bypassing `puppetdb delete-reports`. This workaround will be removed in future releases of peadm after the installer / `puppetdb delete-reports` bug is fixed.

## 2.4.0
### Summary

Readme updates and further convert plan efficiency improvements

### Features

- In the peadm::convert plan, certificates which already contain requested extensions will not be re-issued. This will accelerate the convert process, or allow re-runs of the convert process to move more quickly.

### Improvements

- The README now provides more detailed information on how customers using the peadm module should go about getting support for it.

## 2.3.0
### Summary

Add ability to resume peadm::upgrade or peadm::convert at an intermediate step, rather than requiring re-runs to perform all plan actions from the beginning.

### Features

- Added `begin_at_step` parameter and documentation to peadm::upgrade and peadm::convert

### Bugfixes

- In peadm::convert plan, stop the Puppet agent before writing the csr\_attributes.yaml file, to prevent possible agent interference
- In the peadm::convert plan during finalization, run the Puppet agent on the primary server first, then the rest, to avoid the possibility of a puppetserver restart impacting Puppet agent runs on other systems.

### Improvements

- In the peadm::convert plan, when no peadm\_availability\_group trusted fact is present to identify if compilers should be members of the A pool or B pool, check for pp\_cluster being used to designate this configuration before falling back to a simple even/odd split. This is to catch systems provisioned with the old pe\_xl module, which used pp\_cluster to designate A/B.

## 2.2.1
### Summary

Bugfix release

### Bugfixes

- Fixed problem with `internal_compiler_b_pool_address` parameter name in peadm::action::configure plan

## 2.2.0
### Summary

Reliability fixes for 2019.8.1, README updates, and simpification of the convert plan. New parameters added for `internal_compiler_a_pool_address` and `internal_compiler_b_pool_address` to configure lb addresses for each half of the compiler pool, so that this configuration does not need to be re-applied after upgrades.

### Features

- Added parameters to configure compiler pool addresses for the A and B availability groups. These are used in large and extra large architectures.
- Add basic informational messages to upgrade plan output, to communicate when different stages of the upgrade begin.

### Bugfixes

- Fixed GH-118, wherein a compiler would unnecessarily send duplicate work to an extra configured PuppetDB endpoint.
- Puppet infra upgrade operations now always wait until target nodes are connected before attempting an operation

### Improvements

- Provide a useful overview of the module in the README so that readers can quickly gain a sense of how the module is used, what it affects, and what it does not affect.
- Eliminate `configure_node_groups` parameter to peadm::convert. Perform the correct action(s) automatically.

## Release 2.1.1
### Summary

Development tool and README fixes.

### Bugfixes

- Remove reference to Puppet Support team from README. This module is intended to be used in collaboration with Professional Services and Solutions Architects at Puppet, not Support
- Fixes and improvements to Docker development tools

## Release 2.1.0
### Summary

Support upgrades from PE 2018.1 to 2019.7.

### Features

- Support added for upgrading from PE 2018.1 to 2019.7

## Release 2.0.0
### Summary

Major version release to support PE 2019.7.

Users can use peadm 2.0.0 to create new 2019.7 deployments, or to upgrade from
2019.5 to 2019.7.

To deploy PE 2019.5 or older, use a 1.x release of peadm.

### Features
- Support added for PE 2019.7

## Release 1.2.0
### Summary

Feature and bugfix release.

### Features
- Add direct download option for PE installers (download\_mode parameter)
- Add docker features for testing deployments in containers
- Improve idempotency around CSR submission and signing
- Add basic version validation

### Bugfixes
- Make peadm::read\_file compatible with python3 for better CentOS 8 support
- Fix failure to install when passing passing r10k\_private\_key parameters
- Improve error handling of peadm::download task

## Release 1.1.0
### Summary

This release supports PE 2019.1 through 2019.5.

A Changelog was not maintained prior to this release.

### Features
- Provision new PE clusters with standard, large, or extra-large architecture
- Upgrade PE clusters provisioned with peadm

### Bugfixes

N/A

This changelog is used track changes with this module in human readable format.
Feel free to reference tickets with links or other important information the 
reader would find useful when determining the level of risk with upgrading.
For more information on changelogs please [see the keeping a changelog site](http://keepachangelog.com/en/0.3.0/). 
