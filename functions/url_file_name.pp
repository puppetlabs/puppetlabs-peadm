# @summary The file name a URL's path ends in, without its query string, fragment or user info
#
# A URL can carry credentials in its query string (a pre-signed URL) or its
# user info, and the plans use this name in file paths, task arguments and
# logged parameters (PE-47523). The scheme and the authority (up to the first
# /, ? or #) go first. An @ anywhere after that means user info holding a raw
# / ? or #, where it ends can't be told, so there is no name. Like
# tasks/download.sh, this errs on the side of printing less, so it also
# returns undef for a URL with an @ in its path or query.
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
