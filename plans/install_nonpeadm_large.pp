plan peadm::install_nonpeadm_large(
  TargetSpec $master,
  TargetSpec $compiler,
  TargetSpec $replica,
  String $pe_version = '2023.8.0',
  Optional[String] $arch = 'el-7-x86_64',
) {
  # Construct the installer URL with architecture
  $installer = "puppet-enterprise-${pe_version}-${arch}"
  $installer_url = "https://s3.amazonaws.com/pe-builds/released/${pe_version}/${installer}"

  # Step 1: Download Puppet Enterprise on Master
  run_command("curl -O ${installer_url}.tar.gz", $master)

  # Step 2: Extract the downloaded tarball
  run_command("tar xf ${installer}.tar.gz", $master)

run_command("echo '{
    \"console_admin_password\": \"puppetLabs123!\",
    \"puppet_enterprise::puppet_master_host\": \"${master}\",
    \"puppet_enterprise::profile::master::code_manager_auto_configure\": true
    }' > ${installer}/pe.conf
  ", $master)

  # Step 3: Navigate to the extracted directory and install Puppet Enterprise
  run_command("cd ${installer} && echo 'y' | ./puppet-enterprise-installer -c pe.conf", $master)

  # run puppet on master
  run_task('peadm::puppet_runonce', $master)

  # # Step 5: Install Puppet Agent on the Compiler Node
  run_command("curl -k https://${master}:8140/packages/current/install.bash | bash", $compiler, run_as => 'root')

  # run_task('peadm::puppet_runonce', $master)

  # # # Step 7: Sign the Certificate Request from the Compiler Node on the Master
  run_command("puppetserver ca sign --certname ${compiler}", $master)

  # # Step 6: Run Puppet Agent on the Compiler Node to request certificate
  run_task('peadm::puppet_runonce', $compiler)

  run_command("(echo 'admin'; echo 'puppetLabs123!') | puppet access login --lifetime 1y", $master)

  # # Step 4: Add Compiler Node
  run_command("puppet infrastructure provision compiler ${compiler}", $master)

  run_command("curl -k https://${master}:8140/packages/current/install.bash | bash", $replica, run_as => 'root')

  run_task('peadm::puppet_runonce', $master)

  # # Step 7: Sign the Certificate Request from the Compiler Node on the Master
  run_command("puppetserver ca sign --certname ${replica}", $master)

  # Step 6: Run Puppet Agent on the Compiler Node to request certificate
  run_task('peadm::puppet_runonce', $replica)

  # run_command('puppet code deploy production --wait', $master)

  # Step 5: Add Replica Node
  run_command("puppet infrastructure provision replica ${replica}", $master)

  return 'success'
}
