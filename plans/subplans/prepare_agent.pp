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

    # On primary, if necessary, sign the certificate request. peadm::migrate's
    # purge can revoke the primary's own certificate as a side effect (its
    # serial can coincidentally collide with a purged node's serial).
    # sign_csr's internal `puppetserver ca sign` does a local HTTPS
    # self-check against the primary's own puppetserver before signing, so
    # once the primary's cert is revoked, every sign_csr call fails with
    # "certificate verify failed (certificate revoked)" -- regardless of
    # whose cert is being signed. Detect that specific error and regenerate
    # the primary's own cert via the same disk-level stop/rm/generate/start
    # sequence used in peadm::subplans::modify_certificate (that path never
    # touches the broken HTTPS endpoint), then retry this sign_csr call once.
# lint:ignore:strict_indent
    $sign_result = run_task('peadm::sign_csr', $primary_target, { 'certnames' => [$agent_target.peadm::certname()], '_catch_errors' => true })
    unless $sign_result.ok {
      $sign_output = ($sign_result.error_set.first.value =~ Hash) ? {
        true    => $sign_result.error_set.first.value['_output'],
        default => undef,
      }
      # Match both observed phrasings: sign_csr's own SSL error says
      # "certificate revoked" (lowercase, adjacent); PuppetDB's
      # deactivate_node error (seen in a related variant of this bug) says
      # "Certificate '...' is revoked" (capitalized, not adjacent).
      unless ($sign_output =~ String[1]) and ($sign_output =~ /[Cc]ertificate.*revoked/) {
        fail_plan("peadm::sign_csr failed on ${primary_target.peadm::certname()}: ${sign_output}")
      }
      $primary_certname = $primary_target.peadm::certname()
      out::message("${primary_certname}'s own certificate appears revoked; regenerating it before retrying sign_csr")
      $primary_certdata = run_task('peadm::cert_data', $primary_target).first.value
      $primary_alt_names = [$primary_certname] + ($primary_certdata['dns-alt-names'] - $primary_certname)
      run_task('service', $primary_target, { action => 'stop', name => 'pe-puppetserver' })
      run_command(@("HEREDOC"/L), $primary_target)
              rm -f \
          /etc/puppetlabs/puppet/ssl/certs/${primary_certname}.pem \
          /etc/puppetlabs/puppet/ssl/private_keys/${primary_certname}.pem \
          /etc/puppetlabs/puppet/ssl/public_keys/${primary_certname}.pem \
          /etc/puppetlabs/puppet/ssl/certificate_requests/${primary_certname}.pem \
          /etc/puppetlabs/puppet/ssl/ca/signed/${primary_certname}.pem \
        |-HEREDOC
      run_command(@("HEREDOC"/L), $primary_target)
          /opt/puppetlabs/bin/puppetserver ca generate \
          --certname ${primary_certname} \
          --subject-alt-names ${primary_alt_names.join(',')} \
          --ca-client
        |-HEREDOC
      run_task('service', $primary_target, { action => 'start', name => 'pe-puppetserver' })
      peadm::wait_until_service_ready('all', $primary_target)
      run_task('peadm::sign_csr', $primary_target, { 'certnames' => [$agent_target.peadm::certname()] })
    }
# lint:endignore
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
