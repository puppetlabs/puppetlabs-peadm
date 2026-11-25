# Fails if any nodes have the chosen transport.
#
# Useful for excluding PCP when it's not appopriate
#
# @param nodes Targets whose transports should be checked.
# @param transport Transport protocol to reject, such as pcp.
# @param message Explanation included in the failure when a target uses the rejected transport.
# @return The checked targets when none uses the rejected transport; otherwise raises an error.
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
