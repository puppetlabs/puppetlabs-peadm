plan peadm::util::add_cert_extensions (
  TargetSpec $targets,
  TargetSpec $master_host,
  Hash       $extensions,
  Array      $remove = [ ],
) {
  $all_targets   = peadm::get_targets($targets)
  $master_target = peadm::get_targets($master_host, 1)

  # Short-circuit if there are no targets
  if $all_targets.empty { return(0) }

  # This plan doesn't work to reissue the master cert over the orchestrator due
  # to pe-puppetserver needing to restart
  if ($master_target[0] in $all_targets) {
    $master_target.peadm::fail_on_transport('pcp')
  }

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
        $k =~ /^1\.3\.6\.1\.4\.1\.34380\.1(?!\.3\.39)/ and !($k in $remove)
      })
    })}
  }

  # We'll use these when running commands
  $pserver = '/opt/puppetlabs/bin/puppetserver'
  $puppet  = '/opt/puppetlabs/bin/puppet'

  # Loop through and recert each target one at at time, because Bolt lacks
  # real parallelism
  $all_targets.map |$target| {
    $certname = $certdata[$target]['certname']

    # This will be the new trusted fact data for this node
    $extension_requests = $certdata[$target]['extensions'] + $extensions

    # Everything starts the same; we always stop the agent and revoke the
    # existing cert. We use `run_command` in case the master is 2019.x but
    # the agent is only 2018.x. In that scenario `run_task(service, ...)`
    # doesn't work.
    $was_running = run_command('systemctl is-active puppet.service', $target, _catch_errors => true)[0].ok
    if ($was_running) { run_command('systemctl stop puppet.service', $target) }

    # Make sure the csr_attributes.yaml file on the node matches
    run_plan('peadm::util::insert_csr_extension_requests', $target,
      extension_requests => $extension_requests,
      merge              => false,
    )

    run_command("${pserver} ca clean --certname ${certname}", $master_target)

    # Then things get crazy...

    if ($certname != $master_certname) {
      # AGENT cert regeneration
      run_task('peadm::ssl_clean', $target, certname => $certname)
      run_task('peadm::submit_csr', $target)
      ctrl::sleep(2) # some lag sometimes before the cert is available to sign
      run_task('peadm::sign_csr', $master_target, certnames => [$certname])

      # Use a command instead of a task so that this works for Puppet 5 agents
      # w/ PCP transport. If using a task, we run into problems downloading
      # the task file at this point, because there is no longer a cert file
      # present on the agent.
      run_command(@("HEREDOC"/L), $target)
        ${puppet} ssl download_cert --certname ${certname} || \
        ${puppet} certificate find --ca-location remote ${certname}
        | HEREDOC
    }
    else {
      # MASTER cert regeneration
      # Store the node's current dns-alt-names, for use as a flag restoring
      # them later
      $alt_names_flag = $certdata[$target]['dns-alt-names'] ? {
        undef   => '',
        default => "--subject-alt-names ${certdata[$target]['dns-alt-names'].join(',')}",
      }

      # The docs are broken, and the process is unclean. Sadface.
      run_task('service', $target, {action => 'stop', name => 'pe-puppetserver'})
      run_command(@("HEREDOC"/L), $target)
        rm -f \
          /etc/puppetlabs/puppet/ssl/certs/${certname}.pem \
          /etc/puppetlabs/puppet/ssl/private_keys/${certname}.pem \
          /etc/puppetlabs/puppet/ssl/public_keys/${certname}.pem \
          /etc/puppetlabs/puppet/ssl/certificate_requests/${certname}.pem \
        | HEREDOC
      run_command(@("HEREDOC"/L), $target)
        ${pserver} ca generate \
          --certname ${certname} \
          ${alt_names_flag} \
          --ca-client \
        | HEREDOC
      run_task('service', $target, {action => 'start', name => 'pe-puppetserver'})
    }

    # Fire puppet back up when done
    if ($was_running) { run_command('systemctl start puppet.service', $target) }
  }

  run_command("${puppet} facts upload", $all_targets)
}
