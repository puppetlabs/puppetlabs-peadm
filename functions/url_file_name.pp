# @summary The file name a URL's path ends in, without its query string, fragment or user info
#
# This is the helper behind peadm::url_tarball_name, which is what the plans
# should call: only a name that ends in .tar or .tar.gz is safe to use or
# print. A URL can carry credentials in its query string (a pre-signed URL) or
# its user info, and this name must not. The scheme and the authority (up to the first
# /, ? or #) are dropped first. Any @ after that is taken for user info
# holding a raw / ? or #, where it ends can't be told, so there is no name,
# even when the @ is really in the path or query. This errs on the side of
# printing less, as tasks/download.sh does.
#
# @api private
#
# @param url The URL
#
# @return [Optional[String[1]]] The file name, or undef if the URL's path
#   doesn't end in one, or the URL is ambiguous
function peadm::url_file_name(String[1] $url) >> Optional[String[1]] {
  $rest = $url.regsubst(/\A[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/?#]*/, '')

  if $rest =~ /@/ {
    return(undef)
  }

  $path = $rest.split(/[?#]/)[0]

  # The last path segment, unless the path is empty or ends in a /
  $path ? {
    /(?:\A|\/)([^\/]+)\z/ => $1,
    default               => undef,
  }
}
