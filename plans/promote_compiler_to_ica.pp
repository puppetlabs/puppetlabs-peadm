# @summary Promote an existing CA-proxy compiler to an intermediate CA (ICA) compiler.
#   Implements the full promote workflow: preflight, generate/submit a CSR, poll for operator
#   approval, install the signed certificate, validate independent signing, and print the
#   ica-pool follow-up instructions. See SPEC.md sec 12.2 and Decision S.
# @param compiler FQDN of the compiler to promote.
# @param primary FQDN of the PE primary.
# @param approval_timeout_seconds How long to wait for operator approval before failing.
# @param approval_poll_interval_seconds How often to poll for approval.
# @param replica FQDN of the DR replica, used as the failover candidate if the primary becomes
#   unreachable mid-poll (Decision S). peadm does not discover topology, so this is supplied
#   rather than resolved. When unset, a primary connection failure fails the plan with a message
#   naming this parameter rather than retrying a dead host until timeout.
# @param resume_request_id An existing pending request id, to resume a run whose approval poll
#   timed out. Skips CSR submission and polls the supplied id -- a fresh submission would
#   collide with the still-pending row (409, partial unique index).
plan peadm::promote_compiler_to_ica (
  Peadm::SingleTargetSpec           $compiler,
  Peadm::SingleTargetSpec           $primary,
  Integer[1]                        $approval_timeout_seconds       = 3600,
  Integer[1]                        $approval_poll_interval_seconds = 30,
  Optional[Peadm::SingleTargetSpec] $replica                        = undef,
  Optional[String[1]]               $resume_request_id              = undef,
) {
  $compiler_target = peadm::get_targets($compiler, 1)
  $primary_target  = peadm::get_targets($primary, 1)

  # 1. Preflight. The primary records an ICA as 'active' the moment the
  #    operator approves it, which is BEFORE the certificate reaches the
  #    compiler. So 'active' does not mean "promotion finished": it also
  #    describes a run whose poll timed out and was approved afterwards.
  #    Treat it as "skip submission, resume at install" and let
  #    install_ica_cert's own short-circuit decide whether real work remains.
  $existing = run_task('peadm::get_ica_state', $primary_target,
    compiler_fqdn => $compiler_target.peadm::certname(),
  ).first.value
  $already_provisioned = ($existing['state'] == 'active')
  if $already_provisioned {
    out::message(@("MSG"))
      ${compiler_target} already has an approved ICA on the primary. Skipping submission and
      approval; resuming at certificate install.
      | MSG
  }

  # 2. Generate ICA key pair and submit CSR (runs on the compiler). Skipped
  #    when already provisioned, or when resuming a timed-out run: the
  #    pending request row still exists, and re-submitting collides with it
  #    (409, partial unique index).
  #
  #    $already_provisioned takes precedence over $resume_request_id when
  #    both apply: the primary's live state is more trustworthy than an
  #    operator-supplied id from a possibly-stale prior invocation, and an
  #    already-active ICA means there's nothing left to poll for regardless
  #    of which request id got it there.
  $request_id = if $already_provisioned {
    undef
  } elsif $resume_request_id {
    out::message("Resuming approval poll for request ${resume_request_id}. No new CSR submitted.")
    $resume_request_id
  } else {
    $submission = run_task('peadm::submit_ica_csr', $compiler_target)
    $new_id = $submission.first.value['request-id']
    out::message("ICA request submitted (id: ${new_id}). Waiting for operator approval...")
    out::message('Approve in the PE Console at: /certificates/intermediate-ca')
    $new_id
  }

  # 3. Poll for approval with timeout. poll_ica_approval is a plan, not a
  #    function or task: it must re-target run_task at a different host on a
  #    later iteration when the primary fails over, and only plan-language
  #    control flow can do that.
  $poll = if $already_provisioned {
    { 'approved' => true, 'primary' => $primary_target }
  } else {
    run_plan('peadm::poll_ica_approval',
      primary      => $primary_target,
      request_id   => $request_id,
      probe_target => $compiler_target,
      timeout      => $approval_timeout_seconds,
      interval     => $approval_poll_interval_seconds,
      replica      => $replica,
    )
  }

  # Every later primary-facing step uses this, not $primary_target: after a
  # failover, addressing the original target would fail immediately following
  # a successful approval.
  $current_primary = $poll['primary']

  # Rejection does not return here: poll_ica_approval fails the plan itself,
  # surfacing the primary's rejection-reason. Reaching this branch means the
  # timeout elapsed while the request was still pending, and nothing else.
  if !$poll['approved'] {
    fail_plan(@("MSG"))
      ICA request ${request_id} was still pending after ${approval_timeout_seconds}s. Approve it
      in the PE Console, then either re-run this plan with resume_request_id => '${request_id}'
      to resume polling the same request, or simply re-run it once the request is approved --
      preflight will pick the promotion up at the certificate install. Do not submit a new
      request. If it was rejected, this plan would have failed earlier with the reason.
      | MSG
  }

  # 4. Install signed cert, swap bootstrap, restart CA service (runs on the
  #    compiler). Idempotent: when the compiler already holds this exact
  #    certificate and its bootstrap already loads IntermediateCAService, the
  #    task returns without rewriting config or restarting the service.
  run_task('peadm::install_ica_cert', $compiler_target,
    primary_host => $current_primary.peadm::certname(),
  )

  # 5. Validate: test agent CSR through the new ICA.
  $validation = run_task('peadm::validate_ica_compiler', $compiler_target,
    primary_host => $current_primary.peadm::certname(),
  ).first.value
  unless $validation['valid'] {
    fail_plan("ICA validation failed on ${compiler_target}: ${validation['error']}. The compiler has been reverted to proxy mode.")
  }

  # 6. Inform operator about agent and proxy pool updates. The promotion plan
  #    does NOT automatically update other proxy compilers' ica-pool -- that
  #    is a Puppet catalog change the operator controls via classification.
  out::message(@("MSG"))
    ${compiler_target} is now an ICA compiler.

    Agent configuration:
      Agents currently configured to use ${compiler_target} (via 'server' or 'server_list' in
      puppet.conf) will continue to work -- the compiler now signs certs directly rather than
      proxying. No agent puppet.conf changes are required.

      Agents that connect to this compiler for the first time will receive certs signed by this
      compiler's ICA. Their ca.pem trust bundle (root CA cert) already covers this -- no
      agent-side CA bundle update is needed.

    Proxy compiler pool update:
      To route CSRs from proxy compilers to this new ICA, add its URL to the ica-pool parameter
      in puppet_enterprise::profile::compiler_ica_ca on each proxy compiler and run Puppet on
      those compilers.
    | MSG

  return("${compiler_target} promoted to an ICA compiler")
}
