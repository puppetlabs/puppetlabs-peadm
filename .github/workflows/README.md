# PEADM Workflows for Github Actions

These workflows enable acceptance testing of peadm plans using Github Actions. The Puppet Cloud CI tool from the IAC team is used to provision VMs for testing, and a fixtures module, peadm\_spec, is used to run Bolt-based testing plans. The fixtures module is located in the spec/acceptance/peadm\_spec directory.

## Using workflows

Most workflows start with the same core functionality: provision Cloud CI VMs, then use peadm::provision to install PE. If the installation is successfull, more testing may be performed after that.

If a workflow supports ssh debugging, an optional extra step is added to permit users to ssh into the runner VM prior to the workflow kicking off properly. The credentials and ngrok configuration to enable this must be set as secrets on the Github repository. Once connected, the user can resume flow by touching a "continue" file, and, if they would like flow to pause before tearing down VMs, touch a "pause" file as well. When the pause file is removed, the tear-down will resume.

There are six supported architectures for most tests:

* standard
* standard-with-dr
* large
* large-with-dr
* extra-large
* extra-large-with-dr

### PR Test ###

PRs are tested ONLY when a review is requested. This is to prevent unnecessary and expensive testing runs kicking off simply when filing a PR, waiting instead until a user signals the PR is ready for testing by requesting a review.

### Note for maintainers ###

The `steps:` of each of these three workflows are identical, with the exception of the first step in the debugging flow (which is the ssh step). When modifying the steps of any flow, the others should therefore be updatable with a simple full copy-paste. At some point we should wrap these up into composite flows of their own.
