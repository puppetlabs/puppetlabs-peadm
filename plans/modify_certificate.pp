# @summary Modify the certificate of one or more targets
#
# Certificates can be modified by adding extensions, removing extensions, or
# setting DNS alternative names.
plan peadm::modify_certificate (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $primary_host,
  Hash                    $add_extensions = {},
  Array                   $remove_extensions = [],
  Optional[Array]         $dns_alt_names = undef,
  Boolean                 $force_regenerate = false,
) {
  $all_targets = peadm::get_targets($targets)
  $primary_target = get_target($primary_host)

  # Short-circuit if there are no targets
  if $all_targets.empty { return(0) }

  # TODO: convert $add_extensions and $remov_extensions  to OIDs, if friendly
  # names have been given

  out::message("peadm::modify_certificate: primary host: ${primary_target} - ${primary_target.name} - ${primary_target.uri}")
  $primary_certname = run_task('peadm::cert_data', $primary_target).first['certname']

  # Do the primary first, if it's in the list
  if ($primary_target in $all_targets) {
    run_plan('peadm::subplans::modify_certificate', $primary_target,
      primary_host      => $primary_target,
      primary_certname  => $primary_certname,
      add_extensions    => $add_extensions,
      remove_extensions => $remove_extensions,
      dns_alt_names     => $dns_alt_names,
      force_regenerate  => $force_regenerate,
    )
  }

  # Then do the rest
  parallelize($all_targets - $primary_target) |$target| {
    run_plan('peadm::subplans::modify_certificate', $target,
      primary_host      => $primary_target,
      primary_certname  => $primary_certname,
      add_extensions    => $add_extensions,
      remove_extensions => $remove_extensions,
      dns_alt_names     => $dns_alt_names,
      force_regenerate  => $force_regenerate,
    )
  }

  return('Modified certificates')
}
