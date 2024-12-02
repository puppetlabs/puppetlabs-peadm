function peadm::amend_recovery_defaults_by_pe_version (
  Hash              $base_opts,
  Peadm::Pe_version $pe_version,
  Boolean           $opt_value,
) {
  # work around puppet-lint check_unquoted_string_in_case
  $semverrange = SemVerRange('>= 2023.7')
  case $pe_version {
    $semverrange: {
      $base_opts + {
        'hac' => $opt_value,
      }
    }
    default: {
      $base_opts
    }
  }
}
