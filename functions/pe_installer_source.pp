#
# @summary calculates the PE installer URL and archive name
#
# @param pe_installer_source
#   The URL to download the Puppet Enterprise installer media from. If not
#   specified, PEAdm will attempt to download PE installation media from its
#   standard public source. When specified, PEAdm will download directly from the
#   URL given. Can be an URL, that ends with a /, to a web directory that
#   contains the original archives or an absolute URL to the .tar.gz archive.
#
# @param version
#  The desired version for PE. This is optional for custom provided absolute URLs.
#
# @param platform
#  The platform we're on, for example el-9-x86_64 (osfamily short name - version - arch)
#
# @author Tim Meusel <tim@bastelfreak.de>
#
function peadm::pe_installer_source (
  Optional[Stdlib::HTTPSUrl] $pe_installer_source = undef,
  Optional[Peadm::Pe_version] $version = undef,
  Optional[String[1]] $platform = undef,
) >> Hash[String[1],String[1]] {
  if $pe_installer_source {
    # custom URL ends with /, so we assume it's a webdir with the original installer
    if $pe_installer_source[-1] == '/' {
      assert_type(Peadm::Pe_version, $version)
      assert_type(String[1], $platform)
      $_version          = $version
      $pe_tarball_name   = "puppet-enterprise-${version}-${platform}.tar.gz"
      $pe_tarball_source = "${pe_installer_source}${pe_tarball_name}"
    } else {
      $pe_tarball_name   = $pe_installer_source.split('/')[-1]
      $pe_tarball_source = $pe_installer_source
      $_version          = $pe_tarball_name.split('-')[2]
    }
    $data = { 'url' => $pe_tarball_source, 'filename' => $pe_tarball_name, 'version' => pick($_version,$version), }
  } else {
    assert_type(Peadm::Pe_version, $version)
    assert_type(String[1], $platform)
    $pe_tarball_name   = "puppet-enterprise-${version}-${platform}.tar.gz"
    $pe_tarball_source = "https://s3.amazonaws.com/pe-builds/released/${version}/${pe_tarball_name}"
    $data = { 'url' => $pe_tarball_source, 'filename' => $pe_tarball_name, 'version' => $version }
  }
  $data
}
