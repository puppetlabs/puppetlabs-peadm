# @summary Poll the primary for approval of a pending ICA request, re-targeting to a resolved
#   replica if the primary becomes unreachable mid-poll.
# @param primary The host currently believed to be the PE primary.
# @param request_id The pending ICA request id to poll.
# @param probe_target The compiler being promoted -- the one target proven reachable when the
#   primary is down, where peadm::resolve_current_primary is run.
# @param timeout How long, in seconds, to wait for a terminal state before giving up.
# @param interval How often, in seconds, to poll for a terminal state.
# @param replica FQDN of the DR replica to fail over to if the primary becomes unreachable.
#   Undef disables failover: a connection failure against $primary fails the plan immediately.
plan peadm::poll_ica_approval (
  Peadm::SingleTargetSpec           $primary,
  String[1]                         $request_id,
  Peadm::SingleTargetSpec           $probe_target,
  Integer[1]                        $timeout  = 3600,
  Integer[1]                        $interval = 30,
  Optional[Peadm::SingleTargetSpec] $replica  = undef,
) {
  $probe = peadm::get_targets($probe_target, 1)

  # Puppet's plan language has no native while-loop, so the interval/timeout
  # pair is converted up front into a bounded iteration count. ceiling()
  # ensures a $timeout that isn't an exact multiple of $interval still gets
  # one more poll rather than one fewer.
  $max_polls = Integer(ceiling(Float($timeout) / $interval))

  $initial_state = {
    'terminal' => false,
    'approved' => false,
    'primary'  => peadm::get_targets($primary, 1),
  }

  $final_state = range(1, $max_polls).reduce($initial_state) |$state, $poll_number| {
    if $state['terminal'] {
      $state
    } else {
      if $poll_number > 1 {
        ctrl::sleep($interval)
      }

      $result = run_task('peadm::get_request_status', $state['primary'],
        request_id    => $request_id,
        _catch_errors => true,
      )

      if $result.ok {
        $status = $result.first.value
        case $status['state'] {
          'approved': {
            { 'terminal' => true, 'approved' => true, 'primary' => $state['primary'] }
          }
          'rejected': {
            fail_plan(@("MSG"))
              ICA request ${request_id} was rejected: ${status['rejection-reason']}
              | MSG
          }
          default: {
            # Still pending (or another non-terminal state); keep polling the
            # same target.
            $state
          }
        }
      } else {
        $error = $result.error_set.first.error

        case $error.kind {
          'peadm/ica_request_not_found': {
            # A 404 on the request id is a hard error, not transient: the row
            # genuinely does not exist (rejected and purged, or a bad id), so
            # retrying until timeout would waste the whole window reporting
            # the wrong cause.
            fail_plan(@("MSG"))
              ICA request ${request_id} does not exist on ${state['primary']}: ${error.msg}.
              This is not a timeout -- either the request was rejected and purged, or the
              request id is wrong.
              | MSG
          }
          # This is the kind Bolt's transports (ssh/winrm/docker/etc.) actually
          # raise on a connection failure (bolt/lib/bolt/node/errors.rb) --
          # not 'bolt/connect-error', which Bolt never emits. Getting this
          # string wrong means every real primary outage falls through to the
          # `default` branch below and fails immediately, never attempting
          # the failover this branch exists for.
          'puppetlabs.tasks/connect-error': {
            # Connection-level failure against the current target only: try
            # to resolve the new primary over the failover candidates.
            if $replica =~ Undef {
              fail_plan(@("MSG"))
                Could not reach primary ${state['primary']} to poll ICA request ${request_id}.
                No failover candidate was supplied via the replica parameter: ${error.msg}
                | MSG
            }

            $replica_candidates = peadm::get_targets($replica).map |$target| { $target.peadm::certname() }
            $resolve_result = run_task('peadm::resolve_current_primary', $probe,
              candidates    => $replica_candidates,
              _catch_errors => true,
            )

            unless $resolve_result.ok {
              fail_plan(@("MSG"))
                Primary ${state['primary']} became unreachable while polling ICA request ${request_id},
                and peadm::resolve_current_primary itself failed on ${probe}: ${resolve_result.error_set.first.error.msg}
                | MSG
            }

            $resolved = $resolve_result.first.value

            if $resolved['error'] {
              fail_plan(@("MSG"))
                Primary ${state['primary']} became unreachable while polling ICA request ${request_id},
                and no failover candidate answered: ${resolved['error']}
                | MSG
            }

            out::message(@("MSG"))
              Primary ${state['primary']} became unreachable; resuming polling of request
              ${request_id} against ${resolved['resolved_from']}.
              | MSG

            # $new_state must be a separate statement, not returned inline: a
            # bare hash literal directly after the out::message(...) heredoc
            # call is a Puppet parse ambiguity (parsed as a trailing block on
            # the call), not valid Puppet syntax here.
            $new_state = { 'terminal' => false, 'approved' => false, 'primary' => peadm::get_targets($resolved['resolved_from'], 1) }
            $new_state
          }
          default: {
            fail_plan("Failed to poll ICA request ${request_id} status on ${state['primary']}: ${error.msg}")
          }
        }
      }
    }
  }

  return({ 'approved' => $final_state['approved'], 'primary' => $final_state['primary'] })
}
