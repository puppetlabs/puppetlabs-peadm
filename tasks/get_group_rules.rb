#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'puppet'

# GetInfrastructureAgentGroupRules task class
class GetInfrastructureAgentGroupRules
  def execute!
    infrastructure_agent_group = groups.find { |obj| obj['name'] == 'PE Infrastructure Agent' }
    if infrastructure_agent_group
      puts JSON.pretty_generate(infrastructure_agent_group['rule'])
    else
      puts JSON.pretty_generate({ 'error' => 'PE Infrastructure Agent group does not exist' })
    end
  end

  def groups
    net = https(4433)
    res = net.get('/classifier-api/v1/groups')
    JSON.parse(res.body)
  end

  def https(port)
    https = Net::HTTP.new(Puppet.settings[:certname], port)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    https
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  GetInfrastructureAgentGroupRules.new.execute!
end
