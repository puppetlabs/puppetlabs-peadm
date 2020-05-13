function peadm::oid (
  String $short_name,
) {
  case $short_name {
    'peadm_role':  { '1.3.6.1.4.1.34380.1.1.9812' }
    'peadm_availability_group': { '1.3.6.1.4.1.34380.1.1.9813' }
    'pp_application': { '1.3.6.1.4.1.34380.1.1.8' }
    'pp_cluster': { '1.3.6.1.4.1.34380.1.1.16' }
    'pp_auth_role': { '1.3.6.1.4.1.34380.1.3.13' }
    default: { fail("No peadm OID for ${short_name}") }
  }
}
