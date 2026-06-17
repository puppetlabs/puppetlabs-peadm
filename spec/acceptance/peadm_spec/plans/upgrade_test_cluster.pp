plan peadm_spec::upgrade_test_cluster(
  String[1]           $architecture,
  String              $download_mode             = 'direct',
  Optional[String[1]] $version                   = undef,
  Optional[String[1]] $pe_installer_source       = undef,
  Boolean             $permit_unsafe_versions    = false,
  # PE-44247: when set, force a major PostgreSQL upgrade (e.g. PG14 -> PG17) by
  # writing puppet_enterprise::postgres_version_override into the primary's pe.conf
  # before the upgrade runs. Setting it only on the primary is sufficient to carry
  # the replica across the major boundary too: peadm::upgrade runs
  # `puppet infrastructure upgrade` on each node, and the replica routes on the
  # override-aware requested_postgres_version from the primary's classification --
  # the path PE-44245 fixed.
  Optional[String[1]] $postgres_version_override = undef,
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

  # PE-44247: force a PG-major upgrade by setting the override in the primary's
  # pe.conf before peadm::upgrade. Done here (post-install, pre-upgrade) so the
  # cluster still installs on the UPGRADE_FROM version's default PG major and only
  # crosses majors during the upgrade -- mirroring pe_acceptance_tests'
  # setup/high_availability/force_postgres17_override.rb stopgap on the legacy path.
  if $postgres_version_override =~ NotUndef {
    $primary = $t.filter |$n| { $n.vars['role'] == 'primary' }
    $current_pe_conf = peadm::get_pe_conf($primary[0])
    $updated_pe_conf = $current_pe_conf + {
      'puppet_enterprise::postgres_version_override' => $postgres_version_override,
    }
    peadm::update_pe_conf($primary[0], $updated_pe_conf)
    out::message("PE-44247: set postgres_version_override = ${postgres_version_override} in the primary's pe.conf for the upgrade")
  }

  $params = $arch_params + $common_params
  run_plan('peadm::upgrade', $params)
}
