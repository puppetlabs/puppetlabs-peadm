# @summary The tarball file name a URL ends in, or undef if it doesn't end in one
#
# This is peadm::url_file_name, kept only when the name ends in .tar or
# .tar.gz and is made of letters, digits and . _ + - . The plans use it for
# the PE tarball's name, which ends up in file paths and shell commands, and
# for what they log of pe_installer_source, so any other file name, which can
# be a token, is neither used nor printed.
#
# @api private
#
# @param url The URL
#
# @return [Optional[String[1]]] The tarball file name, or undef
function peadm::url_tarball_name(String[1] $url) >> Optional[String[1]] {
  $name = peadm::url_file_name($url)

  $name ? {
    /\A[A-Za-z0-9._+-]+\.tar(\.gz)?\z/ => $name,
    default                            => undef,
  }
}
