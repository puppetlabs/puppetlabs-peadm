function peadm::file_or_content(
  String                 $param_name,
  Variant[String, Undef] $file,
  Variant[String, Undef] $content,
) {
  $value = [
    $file,
    $content,
  ].peadm::flatten_compact.size ? {
    0 => undef, # no key data supplied
    2 => fail("Must specify either one or neither of ${param_name}_file and ${param_name}_content; not both"),
    1 => $file ? {
      String  => file($file), # file path supplied, read data from file
      undef   => $content,    # content supplied directly, use as-is
    },
  }
}
