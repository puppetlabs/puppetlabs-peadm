plan peadm_spec::provision_test_cluster (
  $provider,
  $architecture,
  $image,
) {
  # Read and parse metadata.json
  $metadata = parsejson(file('./.modules/peadm/metadata.json'))
  out::message("peadm module metadata: ${metadata}")
  # Get the version value
  $module_version = $metadata['version']
  out::message("peadm module version: ${module_version}")

  $nodes =
    case $architecture {
      'standard': {
        ['primary']
      }
      'standard-with-dr': {
        ['primary', 'replica']
      }
      'standard-and-spare-replica': {
        ['primary', 'spare-replica']
      }
      'standard-with-dr-and-spare-replica': {
        ['primary', 'replica', 'spare-replica']
      }
      'large': {
        ['primary', 'compiler']
      }
      'large-with-two-compilers': {
        ['primary', 'compiler', 'compiler']
      }
      'large-with-dr': {
        ['primary', 'compiler', 'replica', 'compiler']
      }
      'large-and-spare-replica': {
        ['primary', 'compiler', 'compiler', 'spare-replica']
      }
      'large-with-dr-and-spare-replica': {
        ['primary', 'compiler', 'replica', 'compiler', 'spare-replica']
      }
      'extra-large': {
        ['primary', 'primary-pdb-postgresql', 'compiler']
      }
      'extra-large-with-dr': {
        ['primary', 'primary-pdb-postgresql', 'compiler', 'replica', 'replica-pdb-postgresql', 'compiler']
      }
      'standard-with-extra-compiler': {
        ['primary', 'unconfigured-compiler']
      }
      'large-with-extra-compiler': {
        ['primary', 'compiler', 'unconfigured-compiler']
      }
      'extra-large-with-extra-compiler': {
        ['primary', 'primary-pdb-postgresql', 'compiler', 'unconfigured-compiler']
      }
      'extra-large-and-spare-replica': {
        ['primary', 'primary-pdb-postgresql', 'compiler', 'compiler', 'spare-replica']
      }
      'extra-large-with-dr-and-spare-replica': {
        ['primary', 'primary-pdb-postgresql', 'compiler',
        'replica', 'replica-pdb-postgresql', 'compiler', 'spare-replica']
      }
      'standard-migration': {
        ['primary', 'new-primary']
      }
      'standard-with-dr-migration': {
        ['primary', 'replica', 'new-primary', 'new-replica']
      }
      'large-migration': {
        ['primary', 'compiler', 'new-primary']
      }
      'large-with-dr-migration': {
        ['primary', 'compiler', 'replica', 'compiler', 'new-primary', 'new-replica']
      }
      'extra-large-migration': {
        ['primary', 'primary-pdb-postgresql', 'compiler', 'new-primary', 'new-primary-pdb-postgresql']
      }
      'extra-large-with-dr-migration': {
        ['primary', 'primary-pdb-postgresql', 'compiler', 'replica', 'replica-pdb-postgresql', 'compiler', 'new-primary', 'new-replica', 'new-primary-pdb-postgresql', 'new-replica-pdb-postgresql']
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
