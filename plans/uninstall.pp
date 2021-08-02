# @summary Single-entry-point plan for uninstalling Puppet Enterprise

plan peadm::uninstall (
  Peadm::SingleTargetSpec  $primary_host,
) {
  peadm::assert_supported_bolt_version()

  $primary_target = peadm::get_targets($primary_host, 1)
  $uninstall_result = run_task('peadm::pe_uninstall', $primary_target)

  return([$uninstall_result])
}

