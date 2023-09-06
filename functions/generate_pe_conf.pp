# @summary Generate a pe.conf file in JSON format
#
# @param settings
#   A hash of settings to set in the config file. Any keys that are set to
#   undef will not be included in the config file.
#
function peadm::generate_pe_conf (
  Hash $settings,
)  >> String {
  # Check that console_admin_password is present
  unless $settings['console_admin_password'] =~ String {
    fail('pe.conf must have the console_admin_password set')
  }

  # Remove anything that is undef, then output to JSON (and therefore HOCON,
  # because HOCON is a superset of JSON)
  stdlib::to_json_pretty($settings.filter |$key,$value| {
      $value != undef
  })
}
