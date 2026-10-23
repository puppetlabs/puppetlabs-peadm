# @summary Preserve an existing certificate availability group or assign a default
#
# This keeps A/B a stable, topological identity across role swaps performed
# with PE's own switch_primary tooling: if a node already carries a valid A
# or B extension, that value is kept even if it no longer matches the node's
# current operational role. Only a node with no existing extension falls
# back to $default (e.g. on a fresh conversion, where there's nothing yet to
# preserve).
#
# @param cert_extensions Hash of certname => extensions hash, as gathered by peadm::cert_data
# @param certname The certname of the node being classified
# @param default The group to assign if the node has no existing valid group
# @return The existing valid availability group, or the supplied default.
function peadm::availability_group_for(
  Hash             $cert_extensions,
  Optional[String] $certname,
  Enum['A', 'B']   $default,
) >> Enum['A', 'B'] {
  $existing = $certname ? {
    undef   => undef,
    default => $cert_extensions.dig($certname, peadm::oid('peadm_availability_group')),
  }

  $existing ? {
    'A'     => 'A',
    'B'     => 'B',
    default => $default,
  }
}
