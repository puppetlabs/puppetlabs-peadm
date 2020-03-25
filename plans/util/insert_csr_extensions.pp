plan peadm::util::insert_csr_extensions (
  TargetSpec $targets,
  Hash       $extensions,
  Boolean    $merge = true,
) {
  get_targets($targets).each |$target| {
    $csr_attributes_data = ($csr_file = run_task('peadm::read_file', $target,
      path => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    ).first['content']) ? {
      undef   => { },
      default => $csr_file.parseyaml,
    }

    # If we're merging extension requests, existing requests will be preserved.
    # If we're not merging, only ours will be used; existing requests will be
    # overritten.
    $csr_file_data = $merge ? {
      true  => $csr_attributes_data.deep_merge({'extension_requests' => $extensions}),
      false => ($csr_attributes_data + {'extension_requests' => $extensions}),
    }

    run_task('peadm::mkdir_p_file', $target,
      path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
      content => $csr_file_data.to_yaml,
    )
  }
}
