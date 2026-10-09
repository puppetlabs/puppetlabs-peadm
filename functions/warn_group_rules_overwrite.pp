# @summary Fetch and log the PE Infrastructure Agent group's current rules
#   before they get overwritten by a classification reassertion
#
# This is diagnostic only -- the fetched rules aren't consumed by anything
# else -- so any failure to fetch or parse them (task failure, malformed
# output) degrades to a generic warning instead of raising, to avoid
# aborting whatever protective reassertion step called this.
#
# @param target the target to fetch the PE Infrastructure Agent group's rules from
function peadm::warn_group_rules_overwrite(Peadm::SingleTargetSpec $target) {
  $rules_result = run_task('peadm::get_group_rules', $target, { '_catch_errors' => true }).first
  if $rules_result.ok {
    $rules_formatted = stdlib::to_json_pretty(parsejson($rules_result.value['_output'], { 'error' => 'unparseable output' }))
    out::message("WARNING: The following existing rules on the PE Infrastructure Agent group will be overwritten with default values:\n ${rules_formatted}")
  } else {
    out::message('WARNING: Could not fetch PE Infrastructure Agent group rules for logging; continuing with reassertion.')
  }
}
