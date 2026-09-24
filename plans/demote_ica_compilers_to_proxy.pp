# @api public
#
# @summary Demote one or more ICA compilers back to CA-proxy compilers.
#
# Per batch: drains each compiler's ICA, waits one quiet period for proxy
# compilers to pick up the change, restores CA-proxy config and restarts
# pe-puppetserver, removes its local passphrase file, then decommissions (or,
# with $revoke, revokes) the ICA -- cleanup is ordered before the
# decommission/revoke call since it is the one step with no retry path once
# it succeeds. Batches run sequentially and are checkpoints: a failed batch
# leaves every later batch untouched.
#
# @param primary_host The PE primary.
# @param compilers The ICA compiler(s) to demote. Mutually exclusive with $all.
# @param all Demote every active-or-draining ICA compiler in the fleet, resolved
#   via peadm::list_compiler_icas. Mutually exclusive with $compilers.
# @param batch_size How many compilers to drain and demote per batch. Defaults to
#   1 -- draining more than one at once removes them from every proxy compiler's
#   pool simultaneously, and with ica-pool-fallback-to-primary enabled that can
#   send the whole fleet's CA signing load to the primary.
# @param acknowledge_fleet_impact Required when $all resolves more compilers than
#   $batch_size, since that combination demotes the fleet across multiple batches
#   without a pause between them for an operator to reassess.
# @param revoke Revoke the ICA (invalidating every agent certificate it signed)
#   instead of the default graceful decommission.
# @param quiet_period_seconds How long to wait per batch after draining, so proxy
#   compilers finish excluding the draining ICA(s) from their pool before this
#   plan swaps DNS/config out from under them. Defaults to 600s -- twice
#   ica-pool-refresh-interval-seconds's own 300s default.
# @param proxy_target Where a demoted compiler should forward CSRs once running
#   as a proxy again: "primary", or a URL for an ICA pool member.
# @param token_file Path to an RBAC token file granting
#   certificate_authority:sign_ica, used for the drain/revoke/decommission
#   calls. Defaults to ~/.puppetlabs/token (the file `puppet access login`
#   writes).
plan peadm::demote_ica_compilers_to_proxy (
  Peadm::SingleTargetSpec $primary_host,
  Optional[TargetSpec]    $compilers                = undef,
  Boolean                 $all                       = false,
  Integer[1]              $batch_size                = 1,
  Boolean                 $acknowledge_fleet_impact  = false,
  Boolean                 $revoke                    = false,
  Integer[0]              $quiet_period_seconds      = 600,
  String[1]               $proxy_target              = 'primary',
  Optional[String[1]]     $token_file                = undef,
) {
  if $all and $compilers != undef {
    fail_plan("peadm::demote_ica_compilers_to_proxy: specify either \$all or \$compilers, not both (\$compilers was '${compilers}').")
  }

  if !$all and $compilers == undef {
    fail_plan('peadm::demote_ica_compilers_to_proxy: specify either $all => true or a $compilers target.')
  }

  $primary_target = peadm::get_targets($primary_host, 1)

  $candidate_fqdns = if $all {
    $list_outcome = catch_errors() || {
      run_task('peadm::list_compiler_icas', $primary_target, 'format' => 'json').first.value['intermediate-cas']
    }

    if $list_outcome =~ Error {
      fail_plan("peadm::demote_ica_compilers_to_proxy: failed to list compiler ICAs on ${primary_host}: ${list_outcome.message}")
    }

    $list_outcome.filter |$ica| { $ica['state'] in ['active', 'draining'] }.map |$ica| { $ica['compiler-fqdn'] }
  } else {
    peadm::get_targets($compilers).map |$target| { $target.peadm::certname() }
  }

  if $all and $candidate_fqdns.length > $batch_size and !$acknowledge_fleet_impact {
    fail_plan([
        "peadm::demote_ica_compilers_to_proxy: \$all resolved ${candidate_fqdns.length} ICA compilers,",
        "more than \$batch_size (${batch_size}). Demoting the whole fleet across multiple batches degrades",
        'CA availability while each batch drains. Set $acknowledge_fleet_impact => true to proceed, or',
        'lower $batch_size to run additional batches yourself.',
    ].join(' '))
  }

  # Preflight: a compiler with no live ICA (never promoted, or already fully
  # demoted) is skipped rather than treated as an error -- re-running this
  # plan after a successful demote should be a no-op, not a failure.
  $preflight = $candidate_fqdns.map |$fqdn| {
    $state_outcome = catch_errors() || {
      run_task('peadm::get_ica_state', $primary_target, 'compiler_fqdn' => $fqdn).first.value['state']
    }

    if $state_outcome =~ Error {
      fail_plan("peadm::demote_ica_compilers_to_proxy: failed to look up ICA state for ${fqdn}: ${state_outcome.message}")
    }

    $preflight_entry = { 'fqdn' => $fqdn, 'state' => $state_outcome }
    $preflight_entry
  }

  $skipped = $preflight.filter |$c| { $c['state'] in ['none', 'revoked', 'decommissioned'] }
  $skipped.each |$c| {
    out::message("${c['fqdn']}: no active or draining ICA (state: ${c['state']}) -- skipping.")
  }

  $to_demote = $preflight.filter |$c| { $c['state'] in ['active', 'draining'] }.map |$c| { $c['fqdn'] }

  # peadm::drain_ica_compiler's underlying endpoint requires state 'active'
  # and 409s on a compiler that is already 'draining' -- reached both by a
  # compiler that started this run already draining (e.g. an external
  # drain, or a previous run's drained_incomplete) and by re-running this
  # plan against drained_incomplete as its own failure message advises.
  # Looked up per compiler so the batch loop can skip a redundant drain
  # call instead of failing on one.
  $already_draining = $preflight.reduce([]) |$acc, $c| {
    if $c['state'] == 'draining' { $acc + [$c['fqdn']] } else { $acc }
  }

  if $to_demote.empty {
    out::message('peadm::demote_ica_compilers_to_proxy: no compilers to demote.')
    return({ 'demoted' => [], 'skipped' => $skipped.map |$c| { $c['fqdn'] } })
  }

  $batches = $to_demote.slice($batch_size)

  # Each batch tracks completion per compiler, not just pass/fail for the
  # batch as a whole: with batch_size > 1, a compiler that fully completes
  # the drain, or the restore/restart/decommission/cleanup sequence, before
  # a later compiler in the same batch fails must still be counted as
  # demoted -- attributing it to the failure instead would misreport a
  # compiler that already had its ICA decommissioned or revoked as one that
  # still needs the plan re-run against it. Likewise, a compiler that was
  # successfully drained before a batch-mate failed (in either phase) has a
  # real, fleet-visible side effect -- proxy compilers start excluding it
  # from CSR routing -- so it is tracked separately from compilers the
  # batch failure stopped the plan from touching at all.
  $result = $batches.reduce({ 'demoted' => [], 'drained_incomplete' => [], 'failed_batch' => undef }) |$acc, $batch| {
    if $acc['failed_batch'] != undef {
      $acc
    } else {
      $drain_result = $batch.reduce({ 'drained' => [], 'failed_fqdn' => undef, 'error' => undef, 'kind' => undef }) |$d, $fqdn| {
        if $d['failed_fqdn'] != undef {
          $d
        } elsif $fqdn in $already_draining {
          { 'drained' => $d['drained'] + [$fqdn], 'failed_fqdn' => undef, 'error' => undef, 'kind' => undef }
        } else {
          $drain_outcome = catch_errors() || {
            run_task('peadm::drain_ica_compiler', $primary_target, 'compiler_fqdn' => $fqdn, 'token_file' => $token_file)
            undef
          }

          if $drain_outcome =~ Error {
            $drain_failure = {
              'drained' => $d['drained'],
              'failed_fqdn' => $fqdn,
              'error' => $drain_outcome.message,
              'kind' => peadm::safe_error_kind($drain_outcome),
            }
            $drain_failure
          } else {
            { 'drained' => $d['drained'] + [$fqdn], 'failed_fqdn' => undef, 'error' => undef, 'kind' => undef }
          }
        }
      }

      if $drain_result['failed_fqdn'] != undef {
        {
          'demoted' => $acc['demoted'],
          'drained_incomplete' => $acc['drained_incomplete'] + $drain_result['drained'],
          'failed_batch' => {
            'compilers' => [$drain_result['failed_fqdn']],
            'error' => $drain_result['error'],
            'kind' => $drain_result['kind'],
          },
        }
      } else {
        # Skip the wait when every compiler in the batch was already draining
        # coming in -- no drain call ran this pass, so there is nothing new
        # for proxy compilers to pick up.
        unless $batch.all |$fqdn| { $fqdn in $already_draining } {
          ctrl::sleep($quiet_period_seconds)
        }

        $finish_result = $batch.reduce({ 'demoted' => [], 'failed_fqdn' => undef, 'error' => undef, 'kind' => undef }) |$f, $fqdn| {
          if $f['failed_fqdn'] != undef {
            $f
          } else {
            $step_outcome = catch_errors() || {
              $compiler_target = peadm::get_targets($fqdn, 1)

              run_task('peadm::restore_ca_proxy_bootstrap', $compiler_target, 'proxy_target' => $proxy_target)
              run_task('peadm::restart_ca_service', $compiler_target)

              # Deliberately ordered before revoke/decommission, not after:
              # cleanup is compiler-local and does not depend on the
              # primary's decommission/revoke call succeeding (the
              # passphrase file is only needed to decrypt the private key
              # for local signing, which restart_ca_service has already
              # taken this compiler out of). Revoke/decommission is the one
              # step in this sequence with no retry path once it succeeds --
              # preflight treats a revoked/decommissioned ICA as already
              # demoted and skips it -- so putting it last would leave a
              # cleanup failure permanently unretryable and silently
              # reported as "re-run this plan," which does nothing.
              run_task('peadm::cleanup_ica_key_material', $compiler_target)

              if $revoke {
                run_task('peadm::revoke_compiler_ica', $primary_target, 'compiler_fqdn' => $fqdn, 'token_file' => $token_file)
              } else {
                run_task('peadm::decommission_compiler_ica', $primary_target, 'compiler_fqdn' => $fqdn, 'token_file' => $token_file)
              }
              undef
            }

            if $step_outcome =~ Error {
              $step_failure = {
                'demoted' => $f['demoted'],
                'failed_fqdn' => $fqdn,
                'error' => $step_outcome.message,
                'kind' => peadm::safe_error_kind($step_outcome),
              }
              $step_failure
            } else {
              { 'demoted' => $f['demoted'] + [$fqdn], 'failed_fqdn' => undef, 'error' => undef, 'kind' => undef }
            }
          }
        }

        if $finish_result['failed_fqdn'] != undef {
          # The compiler whose finish-phase step failed was, unlike a
          # drain-phase failure, already drained -- the whole batch's drain
          # succeeded before this phase started. It carries the same
          # already-excluded-from-CSR-routing caveat as the rest of
          # $incomplete_in_batch, so it belongs in drained_incomplete too,
          # in addition to being named as the specific failure in
          # failed_batch.
          $incomplete_in_batch = $batch - $finish_result['demoted'] - [$finish_result['failed_fqdn']]
          $batch_result = {
            'demoted' => $acc['demoted'] + $finish_result['demoted'],
            'drained_incomplete' => $acc['drained_incomplete'] + $incomplete_in_batch + [$finish_result['failed_fqdn']],
            'failed_batch' => {
              'compilers' => [$finish_result['failed_fqdn']],
              'error' => $finish_result['error'],
              'kind' => $finish_result['kind'],
            },
          }
          $batch_result
        } else {
          $batch_result = {
            'demoted' => $acc['demoted'] + $finish_result['demoted'],
            'drained_incomplete' => $acc['drained_incomplete'],
            'failed_batch' => undef,
          }
          $batch_result
        }
      }
    }
  }

  if $result['failed_batch'] != undef {
    $failed_compilers = $result['failed_batch']['compilers']
    $drained_incomplete = $result['drained_incomplete']
    $not_attempted = $to_demote - $result['demoted'] - $drained_incomplete - $failed_compilers
    $demoted_desc = empty($result['demoted']) ? { true => 'none', default => $result['demoted'].join(', ') }
    $drained_incomplete_desc = empty($drained_incomplete) ? { true => 'none', default => $drained_incomplete.join(', ') }
    $not_attempted_desc = empty($not_attempted) ? { true => 'none', default => $not_attempted.join(', ') }

    # revoke_compiler_ica's crl-updated:false failure is unlike every other
    # failure this plan can hit: the primary has already committed 'revoked'
    # for this ICA before reporting the failure (see that task's own
    # handling), and preflight treats 'revoked' as already-demoted, so the
    # generic "re-run this plan" advice below would silently skip this
    # compiler instead of retrying the CRL splice its revocation isn't real
    # without. Detected precisely via peadm::safe_error_kind, which recovers
    # the underlying task's own _error.kind from the caught error -- see
    # that function's own docstring for why catch_errors()'s wrapped
    # Error.kind alone (always just the generic 'bolt/run-failure') isn't
    # enough on its own.
    $revoke_crl_warning = if $result['failed_batch']['kind'] == 'peadm/revoke_compiler_ica_crl_not_updated' {
      [
        " ${$failed_compilers.join(', ')}'s ICA is now marked revoked at the primary even though this failed --",
        're-running this plan will skip it as already-demoted rather than retry the CRL splice. Investigate the',
        'CRL directly; do not rely on a re-run to fix this one.',
      ].join(' ')
    } else {
      ''
    }

    fail_plan([
        'peadm::demote_ica_compilers_to_proxy: demote failed.',
        "Demoted before the failure: ${demoted_desc}.",
        "Failed batch (${$failed_compilers.join(', ')}): ${result['failed_batch']['error']}.${revoke_crl_warning}",
        'Drained but not finished (their ICA is already excluded from proxy CSR routing --',
        're-run this plan against them to complete the demote, do not treat them as untouched):',
        "${drained_incomplete_desc}.",
        "Not attempted: ${not_attempted_desc}.",
    ].join(' '))
  }

  out::message([
      "peadm::demote_ica_compilers_to_proxy: demoted ${result['demoted'].join(', ')}.",
      "Remove ${result['demoted'].join(', ')} from ica-pool on any peer proxy compilers that still",
      'reference them, since this plan only updates the demoted compilers themselves.',
  ].join(' '))

  return({ 'demoted' => $result['demoted'], 'skipped' => $skipped.map |$c| { $c['fqdn'] } })
}
