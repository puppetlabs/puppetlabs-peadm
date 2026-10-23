# @summary Remove installation console passwords from the local params.json file
# Accepts installer parameters for compatibility; credentials are never used or logged.
# Running PE configuration, logs, other secrets and license files are untouched.
# @param params_file Local JSON file to clean, relative to the Bolt working directory or absolute.
# @param primary_host Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param replica_host Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param compiler_hosts Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param legacy_compilers Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param primary_postgresql_host Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param replica_postgresql_host Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param cloud_database_host Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param console_password Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param version Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param pe_installer_source Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param dns_alt_names Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param compiler_pool_address Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param internal_compiler_a_pool_address Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param internal_compiler_b_pool_address Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param pe_conf_data Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param ldap_config Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param code_manager_auto_configure Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param r10k_remote Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param r10k_private_key_file Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param r10k_private_key_content Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param r10k_known_hosts Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param deploy_environment Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param license_key_file Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param license_key_content Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param stagingdir Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param uploaddir Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param final_agent_state Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param download_mode Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param permit_unsafe_versions Accepted for installer parameter compatibility; unused by this cleanup plan.
# @param token_lifetime Accepted for installer parameter compatibility; unused by this cleanup plan.
plan peadm::remove_secrets_local (
  # Standard
  Peadm::SingleTargetSpec           $primary_host,
  Optional[Peadm::SingleTargetSpec] $replica_host = undef,

  # Large
  Optional[TargetSpec]              $compiler_hosts = undef,
  Optional[TargetSpec]              $legacy_compilers = undef,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Cloud Database
  Optional[Stdlib::Host]            $cloud_database_host = undef,

  # Common Configuration
  Optional[String]                  $console_password = undef,
  Peadm::Pe_version                 $version                          = '2025.12.0',
  Optional[Stdlib::HTTPSUrl]        $pe_installer_source              = undef,
  Optional[Array[String]]           $dns_alt_names                    = undef,
  Optional[String]                  $compiler_pool_address            = undef,
  Optional[String]                  $internal_compiler_a_pool_address = undef,
  Optional[String]                  $internal_compiler_b_pool_address = undef,
  Optional[Hash]                    $pe_conf_data                     = {},
  Optional[Peadm::Ldap_config]      $ldap_config                      = undef,

  # Code Manager
  Optional[Boolean]                 $code_manager_auto_configure = undef,
  Optional[String]                  $r10k_remote              = undef,
  Optional[String]                  $r10k_private_key_file    = undef,
  Optional[Peadm::Pem]              $r10k_private_key_content = undef,
  Optional[Peadm::Known_hosts]      $r10k_known_hosts         = undef,
  Optional[String]                  $deploy_environment       = undef,

  # License Key
  Optional[String]                  $license_key_file    = undef,
  Optional[String]                  $license_key_content = undef,

  # Other
  Optional[String]           $stagingdir             = undef,
  Optional[String]           $uploaddir              = undef,
  Enum['running', 'stopped'] $final_agent_state      = 'running',
  Peadm::Download_mode       $download_mode          = 'bolthost',
  Boolean                    $permit_unsafe_versions = false,
  String                     $token_lifetime         = '1y',
  String[1] $params_file = 'params.json',
) {
  return(peadm::remove_console_password_local($params_file))
}
