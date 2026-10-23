# @summary Resolve a value supplied as a file path or inline content
# @param param_name The parameter prefix used in validation errors.
# @param file Local file to read; mutually exclusive with content.
# @param content Inline value to use; mutually exclusive with file.
# @return The file contents or inline value, or undef when neither is supplied.
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
