function pe_xl::flatten_compact (
  Array $input,
) {
  $input.flatten.reduce([]) |$output, $value| {
    if ($value == undef) {
      $output
    } else {
      $output << $value
    }
  }
}
