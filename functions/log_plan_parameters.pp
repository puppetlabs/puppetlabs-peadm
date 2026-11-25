# @summary Log the PEADM module version and supplied plan parameters
# @param params Parameters to log; callers must exclude credentials and other secrets.
# @return The result of iterating over the supplied parameters.
function peadm::log_plan_parameters(Hash $params) {
  out::message("PEADM Module version: ${peadm::module_version()}")
  $params.each |$key, $value| {
    out::message("Parameter '${key}': [${value}]")
  }
}
