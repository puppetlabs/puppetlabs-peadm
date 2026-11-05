# @summary PE services whose secret keys (/etc/puppetlabs/<service>/conf.d/secrets) encrypt data in their databases
#
# puppet-backup does not include these, so a recovery backup copies them separately.
function peadm::secret_key_services () >> Array[String] {
  [
    'console-services',
    'orchestration-services',
    'infra-assistant',
    'patching-service',
    'workflow-service',
  ]
}
