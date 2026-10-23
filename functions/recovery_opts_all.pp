# @summary Enable every supported recovery scope
# @return A hash with every recovery scope enabled.
function peadm::recovery_opts_all () {
  {
    'activity'     => true,
    'ca'           => true,
    'classifier'   => true,
    'code'         => true,
    'config'       => true,
    'orchestrator' => true,
    'puppetdb'     => true,
    'rbac'         => true,
  }
}
