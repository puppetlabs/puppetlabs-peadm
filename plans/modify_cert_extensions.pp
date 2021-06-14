plan peadm::modify_cert_extensions (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $primary_host,
  Hash                    $add = { },
  Array                   $remove = [ ],
) {
  $all_targets = peadm::get_targets($targets)
  $primary_target = get_target($primary_host)

  # Short-circuit if there are no targets
  if $all_targets.empty { return(0) }

  # TODO: convert $add and $remove to OIDs, if friendly names have been given

  $primary_certname = run_task('peadm::cert_data', $primary_target).first['certname']

  # Do the primary first, if it's in the list
  if ($primary_target in $all_targets) {
    run_plan('peadm::subplans::modify_cert_extensions', $primary_target,
      primary_host     => $primary_target,
      primary_certname => $primary_certname,
      add              => $add,
      remove           => $remove,
    )
  }

  # Then do the rest
  parallelize($all_targets - $primary_target) |$target| {
    run_plan('peadm::subplans::modify_cert_extensions', $target,
      primary_host     => $primary_target,
      primary_certname => $primary_certname,
      add              => $add,
      remove           => $remove,
    )
  }

  return('Modified cert extensions')
}
