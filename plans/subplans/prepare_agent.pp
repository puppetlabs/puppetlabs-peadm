# @api private
plan peadm::subplans::prepare_agent (
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $primary_host,
  Hash                    $certificate_extensions,
  Optional[Array]         $dns_alt_names = undef,
) {

  $agent_target    = peadm::get_targets($targets, 1)
  $primary_target  = peadm::get_targets($primary_host, 1)

  $dns_alt_names_flag = $dns_alt_names? {
    undef   => [],
    default => ["main:dns_alt_names=${dns_alt_names}"],
  }

  $status = run_task('package', $agent_target,
    action => 'status',
    name   => 'puppet-agent').first['status']

  if $status == 'uninstalled' {
    run_plan('peadm::util::insert_csr_extension_requests', $agent_target,
      extension_requests => $certificate_extensions
    )
    run_task('peadm::agent_install', $agent_target,
      server        => $primary_target.peadm::certname(),
      install_flags => $dns_alt_names_flag + [
        '--puppet-service-ensure', 'stopped',
        "main:certname=${agent_target.peadm::certname()}",
      ],
    )
  }

  # Ensures scenarios where agent was pre-installed but never on-boarding and
  # when agent was absent but their was an existing signed certificate with the
  # same name as the one being provisioned.
  #
  # If necessary, manually submit a CSR
  # ignoring errors to simplify logic
  run_task('peadm::submit_csr', $agent_target, {'_catch_errors' => true})

  # On primary, if necessary, sign the certificate request
  run_task('peadm::sign_csr', $primary_target, { 'certnames' => [$agent_target.peadm::certname()] } )

  run_plan('peadm::modify_certificate', $agent_target,
    primary_host   => $primary_target.peadm::certname(),
    add_extensions => $certificate_extensions
  )
}
