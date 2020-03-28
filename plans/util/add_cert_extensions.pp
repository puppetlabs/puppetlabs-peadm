plan peadm::util::add_cert_extensions (
  TargetSpec $targets,
  TargetSpec $master_host,
  Hash       $extensions,
) {
  $all_targets   = peadm::get_targets($targets)
  $master_target = peadm::get_targets($master_host, 1)

  # This plan doesn't work over the orchestrator due to certificates being revoked.
  $all_targets.peadm::fail_on_transport('pcp')

  # The master is treated differently than a standard node, so we need to be
  # able to identify it if it's in the target list
  $master_certname = run_task('peadm::trusted_facts', $master_target)[0]['certname']

  # Get trusted fact information for all targets
  $certdata = run_task('peadm::trusted_facts', $all_targets).reduce({}) |$memo,$result| {
    # Keep the the OID-form trusted fact key/value pairs. If we accidentally
    # include an OID and also a shortname that resolves to the same OID,
    # there'll be a problem trying to sign the cert.
    $memo + { $result.target => ($result.value + {
      'extensions' => ($result['extensions'].filter |$k,$v| {
        $k =~ /^1\.3\.6\.1\.4\.1\.34380\.1(?!\.3\.39)/
      })
    })}
  }

  # We'll use these when running commands
  $pserver = '/opt/puppetlabs/bin/puppetserver'
  $puppet  = '/opt/puppetlabs/bin/puppet'

  # Loop through and recert each target one at at time, because Bolt lacks
  # real parallelism
  $all_targets.map |$target| {

    # This will be the new trusted fact data for this node
    $extension_requests = $certdata[$target]['extensions'] + $extensions

    # Make sure the csr_attributes.yaml file on the node matches
    run_plan('peadm::util::insert_csr_extension_requests', $target,
      extension_requests => $extension_requests,
      merge              => false,
    )

    # Everything starts the same; we always revoke the existing cert
    run_command("${pserver} ca clean --certname ${certdata[$target]['certname']}", $master_target)

    # Then things get crazy...

    # The procedure for regenerating an agent's cert
    if ($certdata[$target]['certname'] != $master_certname) {
      run_command("${puppet} ssl clean --certname ${certdata[$target]['certname']}", $target)
      run_command("${puppet} ssl submit_request --certname ${certdata[$target]['certname']}", $target)
      ctrl::sleep(2) # some lag sometimes before the cert is available to sign
      run_command(@("HEREDOC"/L), $master_target)
        ${pserver} ca sign --certname ${certdata[$target]['certname']} || \
        ${pserver} ca list --certname ${certdata[$target]['certname']} \
        | HEREDOC
      run_command("${puppet} ssl download_cert --certname ${certdata[$target]['certname']}", $target)
    }

    # The procedure for regenerating the master's cert
    else {
      # Store the node's current dns-alt-names, for use as a flag restoring
      # them later
      $alt_names_flag = $certdata[$target]['dns-alt-names'] ? {
        undef   => '',
        default => "--subject-alt-names ${certdata[$target]['dns-alt-names'].join(',')}",
      }

      # The docs are broken, and the process is unclean. Sadface.
      run_command(@("HEREDOC"/L), $target)
        rm -f \
          /etc/puppetlabs/puppet/ssl/certs/${certdata[$target]['certname']}.pem \
          /etc/puppetlabs/puppet/ssl/private_keys/${certdata[$target]['certname']}.pem \
          /etc/puppetlabs/puppet/ssl/public_keys/${certdata[$target]['certname']}.pem \
          /etc/puppetlabs/puppet/ssl/certificate_requests/${certdata[$target]['certname']}.pem \
        | HEREDOC
      run_task('service', $target, {action => 'stop', name => 'pe-puppetserver'})
      run_command(@("HEREDOC"/L), $target)
        ${pserver} ca generate \
          --certname ${certdata[$target]['certname']} \
          ${alt_names_flag} \
          --ca-client \
        | HEREDOC
      run_task('service', $target, {action => 'start', name => 'pe-puppetserver'})
    }
  }

  run_command("${puppet} facts upload", $all_targets)
}
