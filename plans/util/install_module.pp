plan pe_xl::util::install_module(
  TargetSpec $nodes,
  String[1]  $module,
  String[1]  $version,
  String[1]  $stagingdir = '/tmp',
) {

  $module_tarball = "${module.regsubst('/', '-')}-${version}.tar.gz"

  run_plan('pe_xl::util::retrieve_and_upload',
    nodes       => $nodes,
    source      => "https://forge.puppet.com/v3/files/${module_tarball}",
    local_path  => "${stagingdir}/${module_tarball}",
    upload_path => "/tmp/${module_tarball}",
  )

  run_command(@("HEREDOC"), $nodes)
    /opt/puppetlabs/bin/puppet module install \
      --modulepath /etc/puppetlabs/code-staging/environments/production/modules \
      --ignore-dependencies \
      /tmp/${module_tarball}
    | HEREDOC

  run_command('chown -R pe-puppet:pe-puppet /etc/puppetlabs/code-staging', $nodes)
  run_task('pe_xl::code_manager', $nodes,
    action => 'commit',
  )

}
