# @summary Checks PE verison and warns about setting r10k_known_hosts
# Checks if the current PE version is less than 2023.3.0 and the target version is greater than or equal to 2023.3.0
# If both conditions are true and the r10k_known_hosts parameter is not defined, a warning message is displayed.
# @param $current_version [String] The current PE version
# @param $target_version [String] The target PE version
# @param $r10k_known_hosts [Optional[Peadm::Known_hosts]] The r10k_known_hosts parameter
function peadm::check_version_and_known_hosts(
  String $current_version,
  String $target_version,
  Optional[Peadm::Known_hosts]      $r10k_known_hosts         = undef,
) {
  $version = '2023.3.0'
  $current_check = SemVer($current_version) < SemVer($version)
  $target_check = SemVer($target_version) >= SemVer($version)

  # lint:ignore:140chars
  if ($current_check and $target_check and $r10k_known_hosts == undef) {
    out::message( @(HEREDOC/n)
\nWARNING: Starting in PE 2023.3, SSH host key verification is required for Code Manager and r10k.\n
To enable host key verification, you must define the puppet_enterprise::profile::master::r10k_known_hosts parameter with an array of hashes containing "name", "type", and "key" to specify your hostname, key type, and public key for your remote host(s).\n
If you currently use SSH protocol to allow r10k to access your remote Git repository, your Code Manager or r10k code management tool cannot function until you define the r10k_known_hosts parameter.\n
Please refer to the Puppet Enterprise 2023.3 Upgrade cautions for more details.\n
HEREDOC
    )# lint:endignore
  }
}
