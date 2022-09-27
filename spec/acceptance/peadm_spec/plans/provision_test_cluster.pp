plan peadm_spec::provision_test_cluster (
  $provider,
  $architecture,
  $image,
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
      ['primary', 'compiler']
    }
    'large-with-dr': {
      ['primary', 'compiler',
      'replica', 'compiler']
    }
    'extra-large': {
      ['primary', 'primary-pdb-postgresql', 'compiler']
    }
    'extra-large-with-dr': {
      ['primary', 'primary-pdb-postgresql', 'compiler',
      'replica', 'replica-pdb-postgresql', 'compiler']
    }
    default: {
      fail_plan("Unknown architecture: ${architecture}")
    }
  }

  $provision_results =
    # This SHOULD be `parallelize() || {}`. However, provision::* is entirely
  # side-effect based, and not at all parallel-safe.
  $nodes.each |$role| {
    run_task("provision::${provider}", 'localhost',
      action   => 'provision',
      platform => $image,
      vars     => "role: ${role}"
    )
  }

  return($provision_results)
}
