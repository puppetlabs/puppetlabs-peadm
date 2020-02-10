plan peadm::switch_master (
  TargetSpec $nodes,
  String $master,
  Boolean $sign_csr = false,

){

# Extract the target node name and convert to certname array
$certname = get_targets($nodes).map |$a| { $a.name }

  # Task to stop Puppet and change the Puppet Server name in puppet.conf
    run_task ('peadm::agent_switchover',$nodes,
      master => $master
  )

  # If the client does not have csr_attributes.yaml run the plan with sign_csr=true
    if $sign_csr == true {

    # Request a certificate from the master this command will fail so we set _catch_errors,
    # this will allow the plan to run without exiting with an error
      run_task('peadm::puppet_runonce', $nodes,
        noop  =>  true,
        _catch_errors => true
      )

    # The Certificate is signed on the Puppet Server
      run_task('peadm::sign_csr', $master,
        certnames => $certname
      )

    }

  # A certificate is requested and signed with autosign configurtiona and csr_attributes
  # If there is an issue with the agent the plan will exit with an error
    run_task('peadm::puppet_runonce', $nodes,
      noop  =>  true,
      _catch_errors => false
    )

  # Enable the Puppet Service 
    run_task('service', $nodes,
      action => 'start',
      name   => 'puppet',
    )

  return('Switching Puppet Master Certicate Regeneration succeeded')
}
