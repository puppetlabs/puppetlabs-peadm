class pe_xl::role {

  $valid_roles = [
    'pe_xl::master',
    'pe_xl::compiler',
    'pe_xl::puppetdb_database',
    'pe_xl::load_balancer',
  ]

  # Save the trusted pp_role to a shorter variable so it's easier to work with.
  $role = $trusted['extensions']['pp_role']

  if ($role in $valid_roles) {
    include $role
  } elsif ($role in [undef, '']) {
    fail("${trusted['certname']} does not have a pp_role trusted fact!")
  } else {
    fail("${trusted['certname']}'s role is ${role}; not an assignable pe_xl role")
  }

}
