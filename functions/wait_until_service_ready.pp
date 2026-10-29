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
    run_task('peadm::wait_until_service_ready', $target,
      service => $task_service,
      port    => $port,
    )
  }
}
