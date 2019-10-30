# Accept undef or a SingleTargetSpec, and return an Array[Target, 1, 0].
# This differs from get_target() in that:
#   - It returns an Array[Target, 1, 0], rather than a Target
#   - It will accept undef and return [ ].
function pe_xl::get_targets(
  Variant[TargetSpec, Undef] $spec,
  Optional[Integer[1,1]]     $count = undef,
) {
  # If $spec is undef, return an empty array. Otherwise, if $count is 1, return
  # the result of get_target() in an array. If $count is undef, return
  # get_targets().
  $targets = $spec ? {
    undef   => [ ],
    default => $count ? {
      1     => [get_target($spec)],
      undef => get_targets($spec),
    }
  }
}
