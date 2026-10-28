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

  run_task('peadm::wait_until_service_ready', $target,
    service => $task_service,
    port    => $port,
  )
}
