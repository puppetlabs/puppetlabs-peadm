# @summary The file name a URL's path ends in, without its query string, fragment or user info
#
# A URL can carry credentials in its query string (a pre-signed URL) or its
# user info, and the plans use this name in file paths, task arguments and
# logged parameters (PE-47523). The scheme and authority go first, so a
# password holding a raw ? or # can't end up in the name.
#
# @api private
#
# @param url The URL
#
# @return [Optional[String[1]]] The file name, or undef if the URL's path
#   doesn't end in one, or what's left looks like user info
function peadm::url_file_name(String[1] $url) >> Optional[String[1]] {
  $path = $url.regsubst(/\A[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/]*/, '').split(/[?#]/)[0]

  # The last path segment, unless the path ends in a / or the segment holds
  # an @, which would be user info with a raw / in it
  $path ? {
    /(?:\A|\/)([^\/@]+)\z/ => $1,
    default                => undef,
  }
}
