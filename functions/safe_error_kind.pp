# @api private
#
# @summary Recover the kind of the task-level _error a catch_errors() block caught, or undef.
#
# catch_errors() catches any Bolt::Error, but only a Bolt::RunFailure (what
# run_task raises on a failed target) carries a details['result_set'] to
# recover the failing task's own _error.kind from. A different Bolt::Error
# (e.g. one raised by get_target() resolving an ambiguous target, rather
# than by a task) has no result_set at all, so indexing into one
# unconditionally would raise instead of degrading gracefully.
#
# @param error The Error caught from a catch_errors() block.
function peadm::safe_error_kind(
  Error $error,
) {
  $details = $error.details
  $result_set = if $details != undef { $details['result_set'] } else { undef }

  if $result_set != undef {
    $result_set.first.value['_error']['kind']
  } else {
    undef
  }
}
