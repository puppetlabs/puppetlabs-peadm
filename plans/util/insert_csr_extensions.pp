plan peadm::util::insert_csr_extensions (
  TargetSpec $targets,
  Hash       $extensions,
) {
  get_targets($targets).each |$target| {
    $csr_attributes_data = ($csr_file = run_task('peadm::read_file', $target,
      path => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    ).first['content']) ? {
      undef   => { },
      default => $csr_file.parseyaml,
    }

    run_task('peadm::mkdir_p_file', $target,
      path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
      content => $csr_attributes_data.deep_merge({'extension_requests' => $extensions}).to_yaml,
    )
  }
}
