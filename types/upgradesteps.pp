#
# @summary type for the different steps where the peadm::upgrade plan can be started
#
type Peadm::UpgradeSteps = Enum['upgrade-primary', 'upgrade-node-groups', 'upgrade-primary-compilers', 'upgrade-replica', 'upgrade-replica-compilers', 'finalize']
