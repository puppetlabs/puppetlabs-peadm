# @api private
plan peadm::subplans::prepare_agent (
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $primary_host,
  Hash                    $certificate_extensions,
  Optional[Array]         $dns_alt_names = undef,
) {
  $agent_target    = peadm::get_targets($targets, 1)
  $primary_target  = peadm::get_targets($primary_host, 1)

  out::message("Preparing agent ${agent_target} to connect to ${primary_target}")
  out::message("agent target ${agent_target} to connect to ${primary_target}")

  $dns_alt_names_flag = $dns_alt_names? {
    undef   => [],
    default => ["main:dns_alt_names=${dns_alt_names.join(',')}"],
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
  } else {
    run_command('systemctl stop puppet.service', $agent_target)
    # If re-using a node which was previously part of the infrastructure then it
    # might have a bad configuration which will prevent it from reconfiguring. Best
    # example of this is a failed primary being added back into infrastructure  as
    # a replica
    out::message('Ensuring node is set to query current primary for Puppet Agent operations')
    run_command("/opt/puppetlabs/bin/puppet config set --section main server ${primary_target.peadm::certname()}", $agent_target)
    run_command('/opt/puppetlabs/bin/puppet config delete --section agent server_list', $agent_target)
  }

  # Obtain data about certificate from primary 
  $certstatus = run_task('peadm::cert_valid_status', $primary_target,
  certname => $agent_target.peadm::certname()).first.value

  # Obtain data about certificate from agent
  $certdata = run_task('peadm::cert_data', $agent_target).first.value

  # The invalid status is primarily serves as a way to catch revoked certificates.
  # A primary server is the only thing that can reliably identify if agent
  # certificates are revoked, if it is then skip the submit and sign process and
  # just got directly to forcing a regeneration.
  if ($certstatus['certificate-status'] == 'invalid') {
    $force_regenerate = true
    $skip_csr = true
  } else {
    # When the primary can't validate a certificate because it is missing but the
    # agent claims it has one, clean the agent to get to an agreed upon state
    # before moving onto the submit and sign process.
    if $certdata['certificate-exists'] and $certstatus['reason'] =~ /The private key is missing from/ {
      out::message("Agent: ${agent_target.peadm::certname()} has a local cert but Primary: ${primary_target.peadm::certname()} does not, force agent clean") # lint:ignore:140chars
      run_task('peadm::ssl_clean', $agent_target, certname => $agent_target.peadm::certname())
    }
    $force_regenerate = false
    $skip_csr = false
  }

  # Ensures scenarios where agent was pre-installed but never on-boarding and
  # when agent was absent but their was an existing signed certificate with the
  # same name as the one being provisioned.
  #
  # If necessary, manually submit a CSR
  # ignoring errors to simplify logic
  unless $skip_csr {
    run_task('peadm::submit_csr', $agent_target, { '_catch_errors' => true })

    # On primary, if necessary, sign the certificate request
    run_task('peadm::sign_csr', $primary_target, { 'certnames' => [$agent_target.peadm::certname()] })
  }

  # If agent certificate is good but lacks appropriate extensions, plan will still
  # regenerate certificate
  out::message("primary target: ${primary_target}, certname: ${primary_target.peadm::certname()}, uri: ${primary_target[0].uri}")
  run_plan('peadm::modify_certificate', $agent_target,
    primary_host     => $primary_target,
    add_extensions   => $certificate_extensions,
    dns_alt_names    => $dns_alt_names,
    force_regenerate => $force_regenerate
  )
}
