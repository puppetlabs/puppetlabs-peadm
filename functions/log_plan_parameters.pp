function peadm::log_plan_parameters(Hash $params) {
  out::message("PEADM Module version: ${peadm::module_version()}")
  $params.each |$key, $value| {
    # Never print a value whose key looks like it holds a secret (PE-47523).
    $shown = $key =~ /(?i:password|private_key|license|token|secret|ldap_config)/ ? {
      true    => '[redacted]',
      default => $value,
    }
    out::message("Parameter '${key}': [${shown}]")
  }
}
