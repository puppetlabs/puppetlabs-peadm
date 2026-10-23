# @summary Return the default migration recovery scopes
# @return A hash enabling data recovery while excluding code and configuration.
function peadm::migration_opts_default () {
  {
    'activity'     => true,
    'ca'           => true,
    'classifier'   => true,
    'code'         => false,
    'config'       => false,
    'orchestrator' => true,
    'puppetdb'     => true,
    'rbac'         => true,
  }
}
