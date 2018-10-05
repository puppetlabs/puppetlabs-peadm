function pe_xl::flatten_compact (
  Array $input,
) {
  $input.flatten.filter |$value| {
    $value != undef
  }
}
