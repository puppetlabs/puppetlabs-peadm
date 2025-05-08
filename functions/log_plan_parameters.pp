function peadm::log_plan_parameters(Hash $params) {
  out::message("PEADM Module version: ${peadm::module_version()}")
  $params.each |$key, $value| {
    out::message("Parameter '${key}': [${value}]")
  }
}
