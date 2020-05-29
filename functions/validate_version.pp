function peadm::validate_version(
  String $version,
) {
  $supported = ($version =~ SemVerRange('>= 2019.1.0 <= 2019.5.0'))

  unless $supported {
    fail(@("REASON"/L))
      This version of the puppetlabs-peadm module does not support PE ${version}.

      For PE versions older than 2019.1, please use version 0.4.x of the \
      puppetlabs-pe_xl module.

      For PE versions 2019.7 and newer, check to see if a new version of peadm \
      exists which supports that version of PE.

      | REASON
  }
}
