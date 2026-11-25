# @summary Flatten an array and remove undef entries
# @param input The nested array to flatten and compact.
# @return The flattened array with undef values removed.
function peadm::flatten_compact (
  Array $input,
) {
  $input.flatten.filter |$value| {
    $value != undef
  }
}
