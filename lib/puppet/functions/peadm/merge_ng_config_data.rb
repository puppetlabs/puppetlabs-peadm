# frozen_string_literal: true

# @summary
#   This function takes the name of a Node Group and a config data hash,
#   returning the merge of the node group's current config data and the new
#   information specified. It is intended to be used in conjunction with
#   Deferred().
#
# @return
#   Hash
#
# @example
#   $data = Deferred('peadm::merge_ng_config_data', ['PE Master', $new_config_data])
#
Puppet::Functions.create_function(:'peadm::merge_ng_config_data') do
  dispatch :merge_ng_config_data do
    param 'String', :group_name
    param 'Hash', :new_config_data
  end

  def merge_ng_config_data(group_name, new_config_data)
    require_libs
    ensure_config

    ng = Puppet::Util::Nc_https.new
    group = ng.get_groups.select { |g| g['name'] == group_name }.first
    group['config_data'].deep_merge(new_config_data)
  rescue StandardError => e
    Puppet.warn "Error attempting to read and merge node_group config data for #{group_name}: #{e.message}"
    new_config_data
  end

  def require_libs
    require 'deep_merge'

    # We are using utilities from the node_manager module. Load 'em up, trying
    # hard to get at them even if simple requires don't seem to be working.
    begin
      require 'puppet/util/nc_https'
      require 'puppet_x/node_manager/common'
    rescue LoadError
      mod = Puppet::Module.find('node_manager', Puppet[:environment].to_s)
      require File.join mod.path, 'lib/puppet/util/nc_https'
      require File.join mod.path, 'lib/puppet_x/node_manager/common'
    end
  end

  def ensure_config
    # Because of failings in the node_manager module, we have to do some jerry
    # rigging to ensure this will work when running over `bolt apply`.
    return if File.exist?("#{Puppet.settings['confdir']}/node_manager.yaml") ||
              !File.exist?('/etc/puppetlabs/puppet/classifier.yaml')

    config = YAML.load_file('/etc/puppetlabs/puppet/classifier.yaml').first
    config['port'] = 4433
    config['hostcert'] = "/etc/puppetlabs/puppet/ssl/certs/#{config['server']}.pem"
    config['hostprivkey'] = "/etc/puppetlabs/puppet/ssl/private_keys/#{config['server']}.pem"
    config['localcacert'] = '/etc/puppetlabs/puppet/ssl/certs/ca.pem'
    File.open("#{Puppet.settings['confdir']}/node_manager.yaml", 'w') { |f| f.write(config.to_yaml) }
  end
end
