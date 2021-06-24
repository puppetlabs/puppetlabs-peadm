# @return [Boolean] true if the version is supported, raise error otherwise
# @param [String] the version number to check
function peadm::assert_supported_pe_version (
  String $version,
) >> Struct[{'supported' => Boolean}] {
  $supported = ($version =~ SemVerRange('>= 2019.8.5 <= 2021.0.0'))

  unless $supported {
    fail(@("REASON"/L))
      This version of the puppetlabs-peadm module does not support PE ${version}.

      For PE versions older than 2019.8.5, please find and use an older version
      of the peadm module which supports the older version of PE.

      For PE versions newer than 2021.0, check to see if a new version of peadm \
      exists which supports that version of PE.

      | REASON
  }

  return({ 'supported' => $supported })
}
