#
# @summary type for the different steps where the peadm::convert plan can be started
#
type Peadm::ConvertSteps = Enum['modify-primary-certs', 'modify-infra-certs', 'convert-node-groups', 'finalize']
