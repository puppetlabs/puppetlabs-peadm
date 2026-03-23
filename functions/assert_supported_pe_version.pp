# @summary Assert that the PE version given is supported by PEAdm
# @return [Boolean] true if the version is supported, raise error otherwise
# @param [String] the version number to check
function peadm::assert_supported_pe_version (
  String $version,
  Boolean $permit_unsafe_versions = false,
) >> Struct[{ 'supported' => Boolean }] {
  $oldest = '2019.7'
  $newest = '2025.8'
  $supported = ($version =~ SemVerRange(">= ${oldest} <= ${newest}"))

  if $permit_unsafe_versions {
# lint:ignore:strict_indent
    warning(@("WARN"/L))
        WARNING: Permitting unsafe PE versions. This is not supported or tested.
        Proceeding with this action could result in a broken PE Infrastructure.
      | WARN
# lint:endignore
  }

  if (!$supported and $permit_unsafe_versions) {
# lint:ignore:strict_indent
    warning(@("WARN"/L))
        WARNING: PE version ${version} is NOT SUPPORTED!
      | WARN
# lint:endignore
  }
  elsif (!$supported) {
# lint:ignore:strict_indent
    fail(@("REASON"/L))
      This version of the puppetlabs-peadm module does not support PE ${version}.

      For PE versions older than ${oldest}, please check to see if version 1.x \
      or 2.x of the puppetlabs-peadm module supports your PE version.

      For PE versions newer than ${newest}, check to see if a new version of peadm \
      exists which supports that version of PE.

      | REASON
# lint:endignore
  }

  return({ 'supported' => $supported })
}
