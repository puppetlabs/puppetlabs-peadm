# @return [Boolean] true if the version is supported, raise error otherwise
# @param [String] the version number to check
function peadm::validate_version(
  String $version,
) >> Boolean {
  $supported = ($version =~ SemVerRange('>= 2019.7.0 <= 2021.0.0'))

  unless $supported {
    fail(@("REASON"/L))
      This version of the puppetlabs-peadm module does not support PE ${version}.

      For PE versions older than 2019.7, please use version 1.x of the \
      puppetlabs-peadm module.

      For PE versions newer than 2021.0, check to see if a new version of peadm \
      exists which supports that version of PE.

      | REASON
  }
  $supported
}
