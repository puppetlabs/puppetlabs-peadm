#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'puppet'
require 'json'

# Class to check the validity of the local agent's certificate.
class CertValidStatus
  def initialize(params)
    @params = params
  end

  def execute!
    Puppet.initialize_settings

    Puppet.settings.use(:agent, :server, :master, :main)

    begin
      cert_provider = Puppet::X509::CertProvider.new
      ssl_provider = Puppet::SSL::SSLProvider.new
      password = cert_provider.load_private_key_password
      ssl_context = ssl_provider.load_context(certname: @params['certname'], password: password)
    rescue Puppet::SSL::CertVerifyError => e
      status = { 'certificate-status' => 'invalid', 'reason' => e.message }
    rescue Puppet::Error => e
      status = { 'certificate-status' => 'unknown', 'reason' => e.message }
    else
      cert = ssl_context.client_chain.first
      status = { 'certificate-status' => 'valid', 'reason' => "Expires - #{cert.not_after}" }
    end

    result = status

    # Put the result to stdout
    puts result.to_json
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  task = CertValidStatus.new(JSON.parse(STDIN.read))
  task.execute!
end
