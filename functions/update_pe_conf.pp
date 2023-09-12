# @summary Update the pe.conf file on a target with the provided hash
# @param target [Bolt::Target] The target to update the pe.conf file on
# @param updated_pe_conf_hash [Hash] The hash to update the pe.conf file with
function peadm::update_pe_conf(Target $target, Hash $updated_pe_conf_hash) {
  # Convert the updated hash back to a pretty JSON string
  $updated_pe_conf_content = stdlib::to_json_pretty($updated_pe_conf_hash)

  # Write the updated content back to pe.conf on the target
  write_file($updated_pe_conf_content, '/etc/puppetlabs/enterprise/conf.d/pe.conf', $target)
}
