# A convenience function to help remember port numbers for services and handle
# running the wait_until_service_ready task
function peadm::wait_until_service_ready(
  String     $service,
  TargetSpec $target,
) {
  $port = case $service {
    'orchestrator-service': { '8143' }
    default: { '8140' }
  }

  run_task('peadm::wait_until_service_ready', $target,
    service => $service,
    port    => $port,
  )
}
