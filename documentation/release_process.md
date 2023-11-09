# Release Process

## Overview

- [ ] Update PE version support in tests, source and create a new Pull Request with the changes (if needed).
- [ ] Ask for a review and merge the Pull Request
- [ ] Tag all Closed Pull Requests that are included in the release with the appropriate labels.
- [ ] Kick off the [Release Prep](https://github.com/puppetlabs/puppetlabs-peadm/actions/workflows/release-prep.yml) action selecting the branch you want to release from and enter the release version number.
- [ ] Review and merge the Release PREP Pull Request. Make sure to verify the checklist items in the Pull Request description.
- [ ] Once the Release Prep Pull Request is merged, Kick off  [Publish module](https://github.com/puppetlabs/puppetlabs-peadm/actions/workflows/release.yml) action selecting the branch you created the Release Prep Pull Request from.
- [ ] Check [Puppet Forge](https://forge.puppet.com/modules/puppetlabs/peadm/readme) to make sure the module was published
