# @summary Single-entry-point plan for uninstalling Puppet Enterprise

plan peadm::uninstall (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  # Common Configuration
  String                            $version       = '2019.8.5',
) {
  peadm::assert_supported_bolt_version()
  peadm::assert_supported_pe_version($version)

  $primary_target = peadm::get_targets($primary_host, 1)
  $uninstall_result = run_task('peadm::pe_uninstall', $primary_target)

  return([$uninstall_result])
}

