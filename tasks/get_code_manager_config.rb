#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'puppet'

# Prints the r10k settings set on the PE Master node group's
# puppet_enterprise::profile::master class, as {"params": {...}}. Settings
# that are not set are left out. peadm::migrate uses this to install the new
# primary with the old primary's Code Manager remote (PE-45912).
class GetCodeManagerConfig
  SETTINGS = [
    'r10k_remote',
    'r10k_private_key',
    'r10k_known_hosts',
    'r10k_git_provider',
    'r10k_proxy',
    'r10k_postrun',
  ].freeze

  GROUPS_PATH = '/classifier-api/v1/groups'

  def execute!
    pe_master = groups.find { |group| group['name'] == 'PE Master' } || {}
    params = pe_master.dig('classes', 'puppet_enterprise::profile::master') || {}
    puts({ 'params' => params.slice(*SETTINGS).compact }.to_json)
  end

  def groups
    response = https.get(GROUPS_PATH)
    unless response.is_a?(Net::HTTPSuccess)
      error!("Classifier returned HTTP #{response.code} for #{GROUPS_PATH}: #{response.body}")
    end
    JSON.parse(response.body)
  rescue SystemCallError, IOError, OpenSSL::OpenSSLError, Net::OpenTimeout, Net::ReadTimeout => e
    error!("Could not reach the classifier at #{GROUPS_PATH}: #{e.message}")
  end

  def https
    https = Net::HTTP.new(Puppet.settings[:certname], 4433)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    https
  end

  private

  def error!(msg)
    puts({ '_error' => { 'msg' => msg, 'kind' => 'peadm/classifier-request-failed' } }.to_json)
    exit 1
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  GetCodeManagerConfig.new.execute!
end
