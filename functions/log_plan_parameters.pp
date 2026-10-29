# @summary Print the PEADM version and a plan's parameters, for debugging
#
# Prints the PEADM module version, then one line per parameter.
#
# A value whose key looks like it holds a secret prints as [redacted]. This
# goes by top-level key name only: it can't catch a secret under an innocuous
# key, or nested inside another value.
#
# @param params The parameter names and values to print
function peadm::log_plan_parameters(Hash[String, Any] $params) {
  out::message("PEADM Module version: ${peadm::module_version()}")
  $params.each |$key, $value| {
    # Keep the pattern in sync with spec/unit/task/sensitive_parameters_spec.rb.
    $shown = ($key =~ /(?i:password|passwd|passphrase|private_key|license|token|secret|credential|api_key|ldap_config)/) ? {
      true    => '[redacted]',
      default => $value,
    }
    out::message("Parameter '${key}': [${shown}]")
  }
}
