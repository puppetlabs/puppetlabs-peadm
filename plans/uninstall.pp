# This plan is in development and currently considered experimental.
#
# @api private
#
# @summary Single-entry-point plan for uninstalling Puppet Enterprise
plan peadm::uninstall (
  TargetSpec $targets,
) {
  peadm::assert_supported_bolt_version()

  $uninstall_results = run_task('peadm::pe_uninstall', $targets)

  return($uninstall_results)
}
