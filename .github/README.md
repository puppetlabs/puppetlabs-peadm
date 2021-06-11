# PEADM Workflows for Github Actions

These workflows enable acceptance testing of peadm plans using Github Actions. The Puppet Cloud CI tool from the IAC team is used to provision VMs for testing, and a fixtures module, peadm\_spec, is used to run Bolt-based testing plans. The fixtures module is located in the spec/fixtures/modules/peadm\_spec directory.

## Smoke test workflows

The three smoke test workflows currently available are:

* pr-test
* manual-smoke-test
* manual-smoke-test-with-debugging

All three workflows have the same core functionality: provision Cloud CI VMs, then use peadm::provision to install PE. If the installation is successfull, the smoke test passed.

The debugging workflow adds an extra step to permit users to ssh into the runner VM prior to the workflow kicking off properly. The credentials and ngrok configuration to enable this must be set as secrets on the Github repository.

There are six supported architectures for the smoke test:

* standard
* standard-with-dr
* large
* large-with-dr
* extra-large
* extra-large-with-dr

### PR Test ###

PRs are tested ONLY when a review is requested. This is to prevent unnecessary and expensive testing runs kicking off simply when filing a PR, waiting instead until a user signals the PR is ready for testing by requesting a review.

### Note for maintainers ###

The `steps:` of each of these three workflows are identical, with the exception of the first step in the debugging flow (which is the ssh step). When modifying the steps of any flow, the others should therefore be updatable with a simple full copy-paste.
