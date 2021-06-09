# @return [Boolean] true if the version is supported, raise error otherwise
# @param [String] the version number to check
function peadm::assert_supported_pe_version (
  String $version,
) >> Struct[{'supported' => Boolean}] {
  $oldest = '2019.7'
  $newest = '2021.2'
  $supported = ($version =~ SemVerRange(">= ${oldest} <= ${newest}"))

  unless $supported {
    fail(@("REASON"/L))
      This version of the puppetlabs-peadm module does not support PE ${version}.

      For PE versions older than ${oldest}, please use version 1.x of the \
      puppetlabs-peadm module.

      For PE versions newer than ${newest}, check to see if a new version of peadm \
      exists which supports that version of PE.

      | REASON
  }

  return({ 'supported' => $supported })
}
