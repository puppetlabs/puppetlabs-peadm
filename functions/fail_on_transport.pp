# Fails if any nodes have the chosen transport.
#
# Useful for excluding PCP when it's not appopriate
#
function pe_xl::fail_on_transport (
  TargetSpec $nodes,
  String     $transport,
) {
  $targets = get_targets($nodes)
  $targets.each |$target| {
    if $target.protocol == $transport {
      fail_plan(
        "${target.name} uses ${transport} transport. This is not supported",
        'unexpected-transport',
        {
          'target'    => $target,
          'transport' => $transport,
        }
      )
    }
  }
}
