# compiler_pool_address (PE-46918) is only forwarded for architectures with
# compilers (large*, extra-large*); peadm::subplans::configure defaults it to
# the primary's certname when unset, so agents would otherwise never reach a
# compiler. The pe_acceptance_tests harness (run_peadm_install) passes it,
# deriving it when there is a single compiler. The architectures that forward
# it below must match the ones with a 'compiler' role in pe_acceptance_tests'
# REQUIRED_ROLES_BY_ARCHITECTURE (lib/puppet_enterprise_acceptance/
# peadm_install_helper.rb).
plan peadm_spec::install_test_cluster (
  String[1]                 $architecture,
  String                    $download_mode          = 'direct',
  Optional[Boolean]         $code_manager_auto_configure = undef,
  Optional[String[1]]       $version                = undef,
  Optional[String[1]]       $pe_installer_source    = undef,
  Boolean                   $permit_unsafe_versions = false,
  Enum['enable', 'disable'] $fips                   = 'disable',
  Optional[String[1]]       $compiler_pool_address  = undef,
  String                    $console_password
) {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  # The provision service always creates n1-standard-2 VMs (7.5 GB, no swap,
  # image-default disk). On PE 2026.0.0 the primary's agent runs fail with
  # "Cannot allocate memory - fork(2)" once the PE JVMs are up, with no OOM
  # kills, which points at the kernel's overcommit check refusing the fork. Swap
  # can't fix it, because a 4 GB swapfile leaves too little disk for the PE
  # install. Always allow overcommit instead; persisted in sysctl.d so it
  # survives the FIPS reboot below.
  run_command(@(OVERCOMMIT), $t)
    echo 'vm.overcommit_memory = 1' > /etc/sysctl.d/99-peadm-ci-overcommit.conf &&
    sysctl -q -w vm.overcommit_memory=1
    | OVERCOMMIT

  if $fips == 'enable' {
    run_command('/bin/fips-mode-setup --enable', $t)
    run_plan('reboot', $t)
    $fips_status = run_command('/bin/fips-mode-setup --check', $t)
    $fips_status.each |$status| {
      out::message("${status.target.name}: ${status.value['stdout']}")
    }
  }

  # CI jobs triggered from forks don't have access to secrets, so use randomized input instead.
  # '$' is deliberately excluded from the charset: the PE installer interpolates the password
  # inside a double-quoted Puppet string, so a '$' followed by word characters fails the install
  # with "Undefined variable".
  if $console_password == '' {
    $cp = run_command(
      'LC_ALL=C tr -dc \'A-Za-z0-9!"#%&\'\\\'\'()*+,-./:;<=>?@[\]^_`{|}~\' </dev/urandom | head -c 30; echo', localhost
    ).first['stdout'].chomp
  } else {
    $cp = $console_password
  }

  $common_params = {
    console_password       => $cp,
    download_mode          => $download_mode,
    code_manager_auto_configure => $code_manager_auto_configure,
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
        primary_host          => $t.filter |$n| { $n.vars['role'] == 'primary' },
        compiler_hosts        => $t.filter |$n| { $n.vars['role'] == 'compiler' },
        compiler_pool_address => $compiler_pool_address,
    } }
    'large-with-dr': {{
        primary_host          => $t.filter |$n| { $n.vars['role'] == 'primary' },
        replica_host          => $t.filter |$n| { $n.vars['role'] == 'replica' },
        compiler_hosts        => $t.filter |$n| { $n.vars['role'] == 'compiler' },
        compiler_pool_address => $compiler_pool_address,
    } }
    'extra-large': {{
        primary_host            => $t.filter |$n| { $n.vars['role'] == 'primary' },
        primary_postgresql_host => $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' },
        compiler_hosts          => $t.filter |$n| { $n.vars['role'] == 'compiler' },
        compiler_pool_address   => $compiler_pool_address,
    } }
    'extra-large-with-dr': {{
        primary_host             => $t.filter |$n| { $n.vars['role'] == 'primary' },
        primary_postgresql_host  => $t.filter |$n| { $n.vars['role'] == 'primary-pdb-postgresql' },
        replica_host             => $t.filter |$n| { $n.vars['role'] == 'replica' },
        replica_postgresql_host  => $t.filter |$n| { $n.vars['role'] == 'replica-pdb-postgresql' },
        compiler_hosts           => $t.filter |$n| { $n.vars['role'] == 'compiler' },
        compiler_pool_address    => $compiler_pool_address,
    } }
    default: { fail('Invalid architecture!') }
  }

  $install_result =
    run_plan('peadm::install', $arch_params + $common_params)

  return($install_result)
}
