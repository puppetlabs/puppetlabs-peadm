# Fails if any nodes have the chosen transport.
#
# Useful for excluding PCP when it's not appopriate
#
function pe_xl::fail_on_transport (
  Variant[String,Array,Target] $nodes,
  String                       $transport,
) {
  case $nodes {
    Array : {
      # If it's an array just apply thi function to each element
      $nodes.each |$n| { $n.pe_xl::fail_on_transport($transport) }
    }
    String : {
      # If it's a string convert it to a target and come back around
      $target = get_targets($nodes)[0]
      $target.pe_xl::fail_on_transport($transport)
    }
    Target : {
      # If it's a target check the transport
      if $nodes.pe_xl::transport == $transport {
        fail_plan(
          "${nodes} uses ${transport} transport. This is not suppprted",
          'unexpected-transport',
          {
            'transport' => $transport,
            'target'    => $nodes,
          }
        )
      }
    }
  }
}
