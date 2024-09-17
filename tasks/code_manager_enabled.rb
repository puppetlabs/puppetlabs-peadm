#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'
require 'puppet'

# GetPEAdmConfig task class
class GetPEAdmConfig
  def initialize(params)
    @host = params['host']
  end

  def execute!
    code_manager_enabled = groups.dig('PE Master', 'classes', 'puppet_enterprise::profile::master', 'code_manager_auto_configure')

    code_manager_enabled_value = code_manager_enabled == true

    puts({ 'code_manager_enabled' => code_manager_enabled_value }.to_json)
  end

  # Returns a GetPEAdmConfig::NodeGroups object created from the /groups object
  # returned by the classifier
  def groups
    @groups ||= begin
      net = https(@host, 4433)
      res = net.get('/classifier-api/v1/groups')
      NodeGroup.new(JSON.parse(res.body))
    end
  end

  def https(host, port)
    https = Net::HTTP.new(host, port)
    https.use_ssl = true
    https.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    https
  end

  # Utility class to aid in retrieving useful information from the node group
  # data
  class NodeGroup
    attr_reader :data

    def initialize(data)
      @data = data
    end

    # Aids in digging into node groups by name, rather than UUID
    def dig(name, *args)
      group = @data.find { |obj| obj['name'] == name }
      if group.nil?
        nil
      elsif args.empty?
        group
      else
        group.dig(*args)
      end
    end
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = GetPEAdmConfig.new(JSON.parse(STDIN.read))
  task.execute!
end
