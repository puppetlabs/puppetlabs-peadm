# @api private
plan peadm::util::insert_csr_extension_requests (
  TargetSpec $targets,
  Hash       $extension_requests,
  Boolean    $merge = true,
) {
  get_targets($targets).each |$target| {
    $csr_attributes_data = ($csr_file = run_task('peadm::read_file', $target,
        path => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    ).first['content']) ? {
      undef   => {},
      default => $csr_file.parseyaml,
    }

    # If we're merging extension requests, existing requests will be preserved.
    # If we're not merging, only ours will be used; existing requests will be
    # overwritten.
    if $merge and !$csr_attributes_data.empty {
      $csr_file_data = $csr_attributes_data.deep_merge({ 'extension_requests' => $extension_requests })
    } else {
      $csr_file_data = $csr_attributes_data + { 'extension_requests' => $extension_requests }
    }

    run_task('peadm::mkdir_p_file', $target,
      path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
      content => stdlib::to_yaml($csr_file_data),
    )
  }
}
