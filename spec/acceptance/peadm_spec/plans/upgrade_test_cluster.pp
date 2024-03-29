plan peadm_spec::upgrade_test_cluster(
  String[1]           $architecture,
  String              $download_mode          = 'direct',
  Optional[String[1]] $version                = undef,
  Optional[String[1]] $pe_installer_source    = undef,
  Boolean             $permit_unsafe_versions = false,
) {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $common_params = {
    download_mode          => $download_mode,
    version                => $version,
    pe_installer_source    => $pe_installer_source,
    permit_unsafe_versions => $permit_unsafe_versions,
  }

  $arch_params =
    case $architecture {
    'standard': {{
        primary_host => $t.filter |$n| { $n.vars['role'] == 'primary' },
    } }
    'standard-with-dr': {{
        primary_host   => $t.filter |$n| { $n.vars['role'] == 'primary' },
        replica_host   => $t.filter |$n| { $n.vars['role'] == 'replica' },
    } }
    'large': {{
        primary_host   => $t.filter |$n| { $n.vars['role'] == 'primary' },
        compiler_hosts => $t.filter |$n| { $n.vars['role'] == 'compiler' },
    } }
    'large-with-dr': {{
        primary_host   => $t.filter |$n| { $n.vars['role'] == 'primary' },
        replica_host   => $t.filter |$n| { $n.vars['role'] == 'replica' },
        compiler_hosts => $t.filter |$n| { $n.vars['role'] == 'compiler' },
    } }
    'extra-large': {{
        primary_host            => $t.filter |$n| { $n.vars['role'] == 'primary' },
        primary_postgresql_host => $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' },
        compiler_hosts          => $t.filter |$n| { $n.vars['role'] == 'compiler' },
    } }
    'extra-large-with-dr': {{
        primary_host             => $t.filter |$n| { $n.vars['role'] == 'primary' },
        primary_postgresql_host  => $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' },
        replica_host             => $t.filter |$n| { $n.vars['role'] == 'replica' },
        replica_postgresql_host  => $t.filter |$n| { $n.vars['role'] == 'replica-pdb-postgresql' },
        compiler_hosts           => $t.filter |$n| { $n.vars['role'] == 'compiler' },
    } }
    default: { fail('Invalid architecture!') }
  }

  $params = $arch_params + $common_params
  run_plan('peadm::upgrade', $params)
}
