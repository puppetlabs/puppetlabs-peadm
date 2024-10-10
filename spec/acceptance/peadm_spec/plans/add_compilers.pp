plan peadm_spec::add_compilers (
  String[1] $architecture,
) {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $primary_host = $t.filter |$n| { $n.vars['role'] == 'primary' }
  $compiler_host = $t.filter |$n| { $n.vars['role'] == 'unconfigured-compiler' }
  $compiler_fqdn = run_command('hostname -f', $compiler_host).first['stdout'].chomp

  run_task('peadm::puppet_runonce', $primary_host)

  $common_params = {
    avail_group_letter => 'A',
  }

  $arch_params =
    case $architecture {
    'standard': {{
        primary_host            => $primary_host,
        primary_postgresql_host => $primary_host,
        compiler_hosts           => $compiler_host,
    } }
    'large': {{
        primary_host            => $primary_host,
        primary_postgresql_host => $primary_host,
        compiler_hosts           => $compiler_host,
    } }
    'extra-large': {{
        primary_host            => $primary_host,
        primary_postgresql_host => $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' },
        compiler_hosts           => $compiler_host,
    } }
    default: { fail('Invalid architecture!') }
  }

  $compiler_count_query = 'inventory[count()] { trusted.extensions.pp_auth_role = "pe_compiler"}'
  $query_result = run_command("/opt/puppetlabs/bin/puppet query \'${compiler_count_query}\'", $primary_host).first['stdout']
  $first_count = parsejson($query_result)[0]['count']

  $result = run_plan('peadm::add_compilers', $arch_params + $common_params)

  $query_result2 = run_command("/opt/puppetlabs/bin/puppet query \'${compiler_count_query}\'", $primary_host).first['stdout']
  $second_count = parsejson($query_result2)[0]['count']

  $compiler_query = "inventory[certname] { trusted.extensions.pp_auth_role = \"pe_compiler\"  and certname = \"${compiler_fqdn}\"}"

  $compiler_json = run_command("/opt/puppetlabs/bin/puppet query \'${compiler_query}\'", $primary_host).first['stdout']
  $compiler = parsejson($compiler_json)

  if $first_count + 1 != $second_count {
    fail('Compiler count did not increase')
  }

  if $compiler == [] {
    fail('Compiler not found')
  }

  return($result)
}
