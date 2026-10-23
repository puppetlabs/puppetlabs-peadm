# frozen_string_literal: true

# @summary Locate node_manager.yaml in the current Puppet configuration directory
Puppet::Functions.create_function(:'peadm::node_manager_yaml_location') do
  # @return [String] The absolute path to node_manager.yaml.
  dispatch :nm_yaml_location do
  end

  def nm_yaml_location
    File.join(Puppet.settings['confdir'], 'node_manager.yaml')
  end
end
