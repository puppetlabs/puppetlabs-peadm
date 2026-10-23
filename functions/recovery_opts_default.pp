# @summary Return the default backup and recovery scopes
# @return A hash enabling CA, code, configuration, and PuppetDB recovery.
function peadm::recovery_opts_default () {
  {
    'activity'     => false,
    'ca'           => true,
    'classifier'   => false,
    'code'         => true,
    'config'       => true,
    'orchestrator' => false,
    'puppetdb'     => true,
    'rbac'         => false,
  }
}
