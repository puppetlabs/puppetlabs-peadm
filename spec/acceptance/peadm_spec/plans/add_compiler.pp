plan peadm_spec::add_compiler (
  String[1] $architecture,
) {

  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $common_params = {
    avail_group_letter => 'A',
  }

  $arch_params =
    case $architecture {
      'large': {{
        primary_host            => $t.filter |$n| { $n.vars['role'] == 'primary' },
        primary_postgresql_host => $t.filter |$n| { $n.vars['role'] == 'primary' },
        compiler_host           => $t.filter |$n| { $n.vars['role'] == 'unconfigured-compiler' },
      }}
      'extra-large': {{
        primary_host            => $t.filter |$n| { $n.vars['role'] == 'primary' },
        primary_postgresql_host => $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' },
        compiler_host           => $t.filter |$n| { $n.vars['role'] == 'unconfigured-compiler' },
      }}
      default: { fail('Invalid architecture!') }
    }

  $result =
    run_plan('peadm::add_compiler', $arch_params + $common_params)

  return($result)
}
