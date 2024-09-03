<!-- markdownlint-disable MD024 -->
# Changelog


All notable changes to this project will be documented in this file.


The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org).


## [v3.22.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.22.0) - 2024-09-03


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.21.0...v3.22.0)


### Fixed


- pe_installer_source: Use Stdlib::HTTPSUrl datatype [#466](https://github.com/puppetlabs/puppetlabs-peadm/pull/466) ([bastelfreak](https://github.com/bastelfreak))


## [v3.21.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.21.0) - 2024-07-15


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.20.0...v3.21.0)


### Added


- PE-38219 - Support air gapped installation while using a Windows as Jump host [#438](https://github.com/puppetlabs/puppetlabs-peadm/pull/438) ([cathal41](https://github.com/cathal41))


## [v3.20.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.20.0) - 2024-07-01


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.19.0...v3.20.0)


### Added


- Add backup/restore plans [#339](https://github.com/puppetlabs/puppetlabs-peadm/pull/339) ([timidri](https://github.com/timidri))


### Other


- [ITHELP-87329] Update test-backup-restore.yaml [#447](https://github.com/puppetlabs/puppetlabs-peadm/pull/447) ([binford2k](https://github.com/binford2k))
- [ITHELP-87329] Update test-backup-restore.yaml [#446](https://github.com/puppetlabs/puppetlabs-peadm/pull/446) ([binford2k](https://github.com/binford2k))
- (PE-37233) Adding add_compiler to test matrix [#434](https://github.com/puppetlabs/puppetlabs-peadm/pull/434) ([ragingra](https://github.com/ragingra))
- Update backup_restore.md [#432](https://github.com/puppetlabs/puppetlabs-peadm/pull/432) ([J-Hunniford](https://github.com/J-Hunniford))


## [v3.19.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.19.0) - 2024-05-08


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.18.1...v3.19.0)


## [v3.18.1](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.18.1) - 2024-04-17


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.18.0...v3.18.1)


## [v3.18.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.18.0) - 2024-04-04


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.17.0...v3.18.0)


## [v3.17.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.17.0) - 2024-02-07


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.16.1...v3.17.0)


### Other


- add environment parameter to puppet_runonce task [#402](https://github.com/puppetlabs/puppetlabs-peadm/pull/402) ([vchepkov](https://github.com/vchepkov))


## [v3.16.1](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.16.1) - 2023-11-23


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.16.0...v3.16.1)


### Other


- (PE-37192) Updating default install version to 2021.7.6 [#406](https://github.com/puppetlabs/puppetlabs-peadm/pull/406) ([ragingra](https://github.com/ragingra))
- (MAINT) Update release_process.md [#405](https://github.com/puppetlabs/puppetlabs-peadm/pull/405) ([Jo-Lillie](https://github.com/Jo-Lillie))


## [v3.16.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.16.0) - 2023-11-08


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.15.1...v3.16.0)


### Added


- (PE-35906) Adding plans for backing up and restoring CA [#400](https://github.com/puppetlabs/puppetlabs-peadm/pull/400) ([ragingra](https://github.com/ragingra))


### Fixed


- peadm::install: Depend code-manager setup on r10k remote presence, not r10k ssh key [#401](https://github.com/puppetlabs/puppetlabs-peadm/pull/401) ([bastelfreak](https://github.com/bastelfreak))


## [v3.15.1](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.15.1) - 2023-10-10


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.15.0...v3.15.1)


### Added


- (#351) code_manager: Switch default to `undef` [#352](https://github.com/puppetlabs/puppetlabs-peadm/pull/352) ([bastelfreak](https://github.com/bastelfreak))


### Fixed


- Fix for plan peadm::add_compiler over pcp transport [#356](https://github.com/puppetlabs/puppetlabs-peadm/pull/356) ([jortencio](https://github.com/jortencio))


## [v3.15.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.15.0) - 2023-10-06


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.14.0...v3.15.0)


### Added


- support configurable installer target upload path [#376](https://github.com/puppetlabs/puppetlabs-peadm/pull/376) ([h0tw1r3](https://github.com/h0tw1r3))


## [v3.14.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.14.0) - 2023-09-15


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.13.1...v3.14.0)


### Added


- (PE-36789) R10k Known hosts upgrade path [#382](https://github.com/puppetlabs/puppetlabs-peadm/pull/382) ([ragingra](https://github.com/ragingra))
- (PE-36580) Add r10k_known_hosts to install plan [#380](https://github.com/puppetlabs/puppetlabs-peadm/pull/380) ([jpartlow](https://github.com/jpartlow))


## [v3.13.1](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.13.1) - 2023-06-27


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.13.0...v3.13.1)


## [v3.13.0](https://github.com/puppetlabs/puppetlabs-peadm/tree/v3.13.0) - 2023-06-26


[Full Changelog](https://github.com/puppetlabs/puppetlabs-peadm/compare/v3.12.0...v3.13.0)


### Added


- Adding /etc/puppetlabs/enterprise/conf.d/pe.conf [#346](https://github.com/puppetlabs/puppetlabs-peadm/pull/346) ([16c7x](https://github.com/16c7x))
- Allow code manager auto configure to be passed as param [#341](https://github.com/puppetlabs/puppetlabs-peadm/pull/341) ([elainemccloskey](https://github.com/elainemccloskey))
