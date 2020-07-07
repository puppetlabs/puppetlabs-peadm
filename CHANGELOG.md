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
