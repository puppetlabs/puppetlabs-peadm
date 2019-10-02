# Generates a pe.conf file, removing undef parameters
#
# @param user_settings
#   A hash of settings to set in the config file. Any keys that are set to
#   undef will not be included in the config file. This is done to reduce the
#   amount of logic required within plans if parameters are not passed in.
#
function pe_xl::generate_pe_conf (
  Hash $settings,
) {
  # Check that console_admin_password is present
  unless $settings['console_admin_password'] =~ String {
    fail('pe.conf must have the console_admin_password set')
  }

  # Define the configuration settings that will be placed in pe.conf by
  # default. These can be overriden by user-supplied values in the $settings
  # hash.
  $defaults = {
    'puppet_enterprise::profile::master::java_args' => {
      'Xmx' => '2048m',
      'Xms' => '512m',
    },
    'puppet_enterprise::profile::console::java_args' => {
      'Xmx' => '768m',
      'Xms' => '256m',
    },
    'puppet_enterprise::profile::orchestrator::java_args' => {
      'Xmx' => '768m',
      'Xms' => '256m',
    },
    'puppet_enterprise::profile::puppetdb::java_args' => {
      'Xmx' => '768m',
      'Xms' => '256m',
    },
  }

  # Merge the defaults with user-supplied settings, remove anything that is
  # undef, then output to JSON (and therefore HOCON, because HOCON is a
  # superset of JSON)
  ($defaults + $settings).filter |$key,$value| {
    $value != undef
  }.to_json_pretty()
}
