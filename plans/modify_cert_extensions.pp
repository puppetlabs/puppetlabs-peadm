# @api private
plan peadm::modify_cert_extensions (
  TargetSpec              $targets,
  Peadm::SingleTargetSpec $primary_host,
  Hash                    $add = { },
  Array                   $remove = [ ],
) {

  out::message(@(EOS))
    The peadm::modify_cert_extensions plan has been deprecated.
    Please use peadm::modify_certificate instead.
    | EOS

  return(
    run_plan('peadm::modify_certificate', $targets,
      primary_host      => $primary_host,
      add_extensions    => $add,
      remove_extensions => $remove,
    )
  )
}
