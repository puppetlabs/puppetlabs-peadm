plan peadm::misc::upgrade_trusted_facts (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $master_host,
  Boolean                 $autosign = false,
) {

  # Convert input into array of Targets
  $all_targets   = peadm::get_targets($targets)
  $master_target = peadm::get_targets($master_host, 1)

  $certdata = run_task('peadm::trusted_facts', $all_targets).reduce({}) |$memo,$result| {
    # Keep the the OID-form trusted fact key/value pairs. If we accidentally
    # include an OID and also a shortname that resolves to the same OID,
    # there'll be a problem trying to sign the cert.
    $memo + { $result.target => ($result.value + {
      'extensions' => ($result['extensions'].filter |$k,$v| {
        $k =~ /^1\.3\.6\.1\.4\.1\.34380\.1/
      })
    })}
  }

  $pserver = '/opt/puppetlabs/bin/puppetserver'
  $puppet  = '/opt/puppetlabs/bin/puppet'

  $upgrade_results = $all_targets.map |$target| {
    $new_trusted = $certdata[$target]['extensions'] + {
      peadm::oid('peadm_role') => $certdata[$target]['extensions'][peadm::oid('pp_application')],
      peadm::oid('peadm_availability_group') => $certdata[$target]['extensions'][peadm::oid('pp_cluster')],
    }

    run_plan('peadm::util::insert_csr_extensions', $target,
      extensions => $new_trusted,
      merge      => false,
    )

    run_command("${pserver} ca clean --certname ${certdata[$target]['certname']}", $master_target)
    run_command("${puppet} ssl clean --certname ${certdata[$target]['certname']}", $target)
    run_command("${puppet} ssl submit_request --certname ${certdata[$target]['certname']}", $target)

    ctrl::sleep(2) # some lag sometimes before the cert is available to sign

    if !$autosign {
      run_command("${pserver} ca sign --certname ${certdata[$target]['certname']}", $master_target)
    }

    run_command("${puppet} ssl download_cert --certname ${certdata[$target]['certname']}", $target)
  }

}
