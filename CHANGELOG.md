# Change log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org).

## [v3.3.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.3.0) (2022-01-05)

[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.2.0...v3.3.0)

### Added

- Support PE 2021.4 [\#229](https://github.com/puppetlabs/puppetlabs-peadm/pull/229) ([reidmv](https://github.com/reidmv))
- Add development and testing option to permit installing unsupported PE versions [\#204](https://github.com/puppetlabs/puppetlabs-peadm/pull/204) ([jarretlavallee](https://github.com/jarretlavallee))

### Fixed

- Fail agent\_install if agent is already installed [\#223](https://github.com/puppetlabs/puppetlabs-peadm/pull/223) ([reidmv](https://github.com/reidmv))
- Catch mv errors when downloading [\#220](https://github.com/puppetlabs/puppetlabs-peadm/pull/220) ([reidmv](https://github.com/reidmv))
- Determine validation key from asc signature file [\#219](https://github.com/puppetlabs/puppetlabs-peadm/pull/219) ([reidmv](https://github.com/reidmv))
- Improve reliability of downloading PE tarball [\#215](https://github.com/puppetlabs/puppetlabs-peadm/pull/215) ([mcka1n](https://github.com/mcka1n))

## [v3.2.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.2.0) (2021-09-20)

[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.1.0...v3.2.0)

### Added

- Add auto-generated REFERENCE.md documentation [\#211](https://github.com/puppetlabs/puppetlabs-peadm/pull/211) ([reidmv](https://github.com/reidmv))
- Make PEAdm a Puppet supported module [\#199](https://github.com/puppetlabs/puppetlabs-peadm/pull/199) ([ody](https://github.com/ody))

### Fixed

- Update documentation to reference supported PE version [\#213](https://github.com/puppetlabs/puppetlabs-peadm/pull/213) ([reidmv](https://github.com/reidmv))
- Fix output of peadm::status when used with multiple clusters [\#209](https://github.com/puppetlabs/puppetlabs-peadm/pull/209) ([reidmv](https://github.com/reidmv))

## [v3.1.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.1.0) (2021-09-10)

[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.0.1...v3.1.0)

### Added

- Support PE 2021.3 [\#203](https://github.com/puppetlabs/puppetlabs-peadm/pull/203) ([reidmv](https://github.com/reidmv))
- Add PE download signature checking [\#201](https://github.com/puppetlabs/puppetlabs-peadm/pull/201) ([timidri](https://github.com/timidri))
- Add task to report on code synchronization status [\#196](https://github.com/puppetlabs/puppetlabs-peadm/pull/196) ([davidsandilands](https://github.com/davidsandilands))
- Add an experimental peadm::uninstall plan [\#195](https://github.com/puppetlabs/puppetlabs-peadm/pull/195) ([mcka1n](https://github.com/mcka1n))
- Remove hardcoded default memory configuration [\#194](https://github.com/puppetlabs/puppetlabs-peadm/pull/194) ([reidmv](https://github.com/reidmv))
- Highlight user-facing plans by hiding internal plans from `bolt plan show` output [\#189](https://github.com/puppetlabs/puppetlabs-peadm/pull/189) ([reidmv](https://github.com/reidmv))
- Add get\_peadm\_config task [\#187](https://github.com/puppetlabs/puppetlabs-peadm/pull/187) ([reidmv](https://github.com/reidmv))
- Replace plan peadm::modify\_cert\_extensions with peadm::modify\_certificate [\#181](https://github.com/puppetlabs/puppetlabs-peadm/pull/181) ([reidmv](https://github.com/reidmv))

### Fixed

- Fix upgrade without replica [\#198](https://github.com/puppetlabs/puppetlabs-peadm/pull/198) ([reidmv](https://github.com/reidmv))
- Fix upgrade bug for token files with newlines [\#193](https://github.com/puppetlabs/puppetlabs-peadm/pull/193) ([reidmv](https://github.com/reidmv))
- Move load\_balancer class to examples [\#183](https://github.com/puppetlabs/puppetlabs-peadm/pull/183) ([reidmv](https://github.com/reidmv))
- Fix GitHub README.md problem [\#182](https://github.com/puppetlabs/puppetlabs-peadm/pull/182) ([reidmv](https://github.com/reidmv))

## [v3.0.1](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.0.1) (2021-06-30)

[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.0.0...v3.0.1)

### Fixed

- Add missing parenthesis to add\_compiler plan [\#177](https://github.com/puppetlabs/puppetlabs-peadm/pull/177) ([timidri](https://github.com/timidri))
- Use absolute links so they render properly on the Forge [\#175](https://github.com/puppetlabs/puppetlabs-peadm/pull/175) ([binford2k](https://github.com/binford2k))

## [v3.0.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.0.0) (2021-06-29)

[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/2.5.0...v3.0.0)

### Changed

- Global rename of primary/replica and postgresql parameters [\#161](https://github.com/puppetlabs/puppetlabs-peadm/pull/161) ([timidri](https://github.com/timidri))
- Language and terminology updates [\#153](https://github.com/puppetlabs/puppetlabs-peadm/pull/153) ([davidsandilands](https://github.com/davidsandilands))

### Added

- Update workflow PE defaults to latest LTS [\#170](https://github.com/puppetlabs/puppetlabs-peadm/pull/170) ([reidmv](https://github.com/reidmv))
- Add add\_replica plan [\#166](https://github.com/puppetlabs/puppetlabs-peadm/pull/166) ([timidri](https://github.com/timidri))
- Support latest PE release [\#157](https://github.com/puppetlabs/puppetlabs-peadm/pull/157) ([ody](https://github.com/ody))
- Add add\_compiler plan [\#154](https://github.com/puppetlabs/puppetlabs-peadm/pull/154) ([timidri](https://github.com/timidri))

### Fixed

- Resolving linting issues [\#165](https://github.com/puppetlabs/puppetlabs-peadm/pull/165) ([davidsandilands](https://github.com/davidsandilands))
- Fix installer exit handling [\#152](https://github.com/puppetlabs/puppetlabs-peadm/pull/152) ([reidmv](https://github.com/reidmv))

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


\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
