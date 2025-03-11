function peadm::migration_opts_default (
  Peadm::Pe_version $pe_version,
) {
  $base_opts = {
    'activity'     => true,
    'ca'           => true,
    'classifier'   => true,
    'code'         => false,
    'config'       => false,
    'orchestrator' => true,
    'puppetdb'     => true,
    'rbac'         => false,
  }
  peadm::amend_recovery_defaults_by_pe_version($base_opts, $pe_version, true)
}
