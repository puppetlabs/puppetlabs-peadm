# A convenience function to help remember port numbers for services and handle
# running the wait_until_service_ready task
function peadm::wait_until_service_ready(
  String     $service,
  TargetSpec $target,
) {
  # 'console-services' and 'puppetdb' are convenience names for this
  # function only -- they're not valid values for the underlying task's own
  # $service param (which means "which named sub-check to query WITHIN
  # whatever's listening on $port", e.g. 'pe-master'/'ca' within
  # puppetserver's own status aggregator on 8140). What we actually want for
  # these two is the aggregate "all" status, just on a different port --
  # console-services and puppetdb are separate JVM processes from
  # puppetserver, each with their own /status/v1/simple endpoint.
  $task_service = $service ? {
    'console-services' => 'all',
    'puppetdb'          => 'all',
    default             => $service,
  }

  $port = case $service {
    'orchestrator-service': { '8143' }
    'console-services':     { '4433' }
    'puppetdb':             { '8081' }
    default:                { '8140' }
  }

  # The underlying task gives up after 60s (20 attempts, 3s apart). That's
  # fine for most callers, but confirmed insufficient live (job 123083763006,
  # PE 2026.0.0 extra-large): orchestration-services' JVM can still be
  # starting up 60s after a fresh `restart`, especially right after several
  # other co-located JVM services were also just bounced in the same cert
  # regen sequence. A single retry (up to ~120s total) absorbs that without
  # changing the task's own behavior for other callers that don't hit this.
  $result = run_task('peadm::wait_until_service_ready', $target,
    { service => $task_service, port => $port, '_catch_errors' => true },
  )
  unless $result.ok {
    # DIAGNOSTIC ONLY (test/wait-retry-validation scratch branch) -- the
    # first attempt above already burned the task's own 60s budget without
    # the port ever responding. Capture what the target itself thinks is
    # going on with the relevant systemd unit before retrying, since a
    # second identical ~60s wait that fails the same way tells us "it's
    # stuck", not "it just needed more time".
    $unit_name = $service ? {
      'orchestrator-service' => 'pe-orchestration-services',
      'console-services'     => 'pe-console-services',
      'puppetdb'             => 'pe-puppetdb',
      default                => 'pe-puppetserver',
    }
    $diag = run_command(@("HEREDOC"/L), $target, '_catch_errors' => true)
      echo "=== systemctl status ${unit_name} ==="; \
      systemctl status ${unit_name} --no-pager -l 2>&1; \
      echo "=== listening on port ${port} ==="; \
      (ss -ltnp 2>&1 || netstat -ltnp 2>&1) | grep -E "LISTEN|${port}" || echo "nothing found"; \
      echo "=== curl against the status endpoint ==="; \
      curl -vk --max-time 10 https://localhost:${port}/status/v1/simple 2>&1; \
      echo "=== last 100 journal lines for ${unit_name} ==="; \
      journalctl -u ${unit_name} --no-pager -n 100 2>&1
      |-HEREDOC
    out::message("wait_until_service_ready diagnostics for ${unit_name} on ${target.peadm::certname()}:\n${diag.first.value['merged_output']}")

    run_task('peadm::wait_until_service_ready', $target,
      service => $task_service,
      port    => $port,
    )
  }
}
