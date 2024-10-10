# @api public
#
# @summary Proxy plan for peadm::add_compilers.
# @param avail_group_letter _ Either A or B; whichever of the two letter designations the compiler are being assigned to
# @param compiler_host _ The hostname and certname of the new compiler
# @param dns_alt_names _ A comma-separated list of DNS alt names for the compiler.
# @param primary_host _ The hostname and certname of the primary Puppet server
# @param primary_postgresql_host _ The hostname and certname of the PE-PostgreSQL server with availability group $avail_group_letter
plan peadm::add_compiler(
  Enum['A', 'B'] $avail_group_letter = 'A' ,
  Optional[String[1]] $dns_alt_names = undef,
  Peadm::SingleTargetSpec $compiler_host,
  Peadm::SingleTargetSpec $primary_host,
  Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef,
) {
  out::message('Warning: The add_compiler plan is deprecated and will be removed in a future release. Please use the add_compilers plan instead. ')
  run_plan('peadm::add_compilers',
    avail_group_letter      => $avail_group_letter,
    dns_alt_names           => $dns_alt_names ? { undef => undef, default => Array($dns_alt_names) },
    compiler_hosts          => $compiler_host,
    primary_host            => $primary_host,
    primary_postgresql_host => $primary_postgresql_host,
  )
}
