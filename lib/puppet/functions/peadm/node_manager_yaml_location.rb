# frozen_string_literal: true

Puppet::Functions.create_function(:'peadm::node_manager_yaml_location') do
  dispatch :nm_yaml_location do
  end

  def nm_yaml_location
    File.join(Puppet.settings['confdir'], 'node_manager.yaml')
  end
end
