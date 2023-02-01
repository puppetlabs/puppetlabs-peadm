# Fails if any nodes have the chosen transport.
#
# Useful for excluding PCP when it's not appopriate
#
function peadm::fail_on_transport (
  TargetSpec $nodes,
  String     $transport,
  String     $message = 'This is not supported.',
) {
  $targets = get_targets($nodes)
  $targets.each |$target| {
    if $target.protocol == $transport {
      fail_plan(
        "${target.name} uses ${transport} transport: ${message}",
        'unexpected-transport',
        {
          'target'    => $target,
          'transport' => $transport,
        }
      )
    }
  }
}
