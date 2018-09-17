function pe_xl::install_module(
  String[1] $target,
  String[1] $module,
  String[1] $version,
  String[1] $stagingdir = '/tmp',
) {

  $module_tarball = "${module.regsubst('/', '-')}-${version}.tar.gz"

  pe_xl::retrieve_and_upload(
    "https://forge.puppet.com/v3/files/${module_tarball}",
    "${stagingdir}/${module_tarball}",
    "/tmp/${module_tarball}",
    $target
  )

  run_command("/opt/puppetlabs/bin/puppet module install --modulepath /etc/puppetlabs/code-staging/environments/production/modules --ignore-dependencies /tmp/${module_tarball}", $target)
  run_command('chown -R pe-puppet:pe-puppet /etc/puppetlabs/code-staging', $target)
  run_task('pe_xl::code_manager', $target,
    action => 'file-sync commit',
  )

}
