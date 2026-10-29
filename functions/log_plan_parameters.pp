function peadm::log_plan_parameters(Hash[String, Any] $params) {
  out::message("PEADM Module version: ${peadm::module_version()}")
  $params.each |$key, $value| {
    # Never print a value whose key looks like it holds a secret (PE-47523).
    # Keep the pattern in sync with spec/unit/task/sensitive_parameters_spec.rb.
    $shown = ($key =~ /(?i:password|passwd|passphrase|private_key|license|token|secret|credential|api_key|ldap_config)/) ? {
      true    => '[redacted]',
      default => $value,
    }
    out::message("Parameter '${key}': [${shown}]")
  }
}
