plan peadm_spec::add_inventory_hostnames(
  String[1] $inventory_file
) {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
    $command = "yq eval '(.groups[].targets[] | select(.uri == \"${target.uri}\").name) = \"${target.vars['certname']}\"' -i ${inventory_file}"
    run_command($command, 'localhost')
  }
}
