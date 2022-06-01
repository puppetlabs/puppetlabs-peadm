#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'puppet'
require 'json'

params = JSON.parse(STDIN.read)

Puppet.initialize_settings

Puppet.settings.use(:agent, :server, :master, :main)

begin
  cert_provider = Puppet::X509::CertProvider.new
  ssl_provider = Puppet::SSL::SSLProvider.new
  password = cert_provider.load_private_key_password
  ssl_context = ssl_provider.load_context(certname: params['certname'], password: password)
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
