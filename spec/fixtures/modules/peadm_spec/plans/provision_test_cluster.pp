plan peadm_spec::provision_test_cluster (
  $architecture = 'standard',
  $provider = 'provision_service',
  $image = 'rhel-7',
) {

  $nodes =
    case $architecture {
      'standard': {
        ['primary']
      }
      'standard-with-dr': {
        ['primary', 'replica']
      }
      'large': {
        ['primary', 'compiler-1']
      }
      'large-with-dr': {
        ['primary', 'compiler-1',
         'replica', 'compiler-2']
      }
      'extra-large': {
        ['primary', 'primary-pdb-postgresql', 'compiler-1']
      }
      'extra-large-with-dr': {
        ['primary', 'primary-pdb-postgresql', 'compiler-1',
         'replica', 'replica-pdb-postgresql', 'compiler-2']
      }
    }

  $provision_results =
    # This SHOULD be `parallelize() || {}`. However, provision::* is entirely
    # side-effect based, and not at all parallel-safe.
    $nodes.each |$target| {
      run_task("provision::${provider}", 'localhost',
        action    => 'provision',
        platform  => $image,
      )
    }

  return($provision_results)
}
