#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'puppet'

# Reads the Code Manager settings of the PE Master node group, for
# peadm::migrate to carry across to the new primary (PE-45912). Prints:
#
#   {"_sensitive": {"settings": {...}}, "not_carried": [...]}
#
# settings: the CARRIED settings set as class parameters of
# puppet_enterprise::profile::master. Bolt wraps _sensitive in Sensitive, so
# the values (an r10k remote URL can hold a credential) stay out of its output
# and logs.
#
# not_carried: names only, never values, of other Code Manager settings on the
# group: the NOT_CARRIED class parameters, and Code Manager entries in the
# group's configuration data.
class GetCodeManagerConfig
  CARRIED = ['r10k_remote', 'r10k_private_key', 'r10k_known_hosts', 'r10k_git_provider'].freeze
  NOT_CARRIED = ['r10k_proxy', 'r10k_postrun'].freeze
  PROFILE = 'puppet_enterprise::profile::master'
  CODE_MANAGER_CLASSES = ['puppet_enterprise::master::code_manager', 'puppet_enterprise::master::code_management'].freeze
  GROUPS_PATH = '/classifier-api/v1/groups'

  def execute!
    pe_master = groups.find { |group| group['name'] == 'PE Master' }
    error!("The classifier at #{url} has no 'PE Master' node group.", 'peadm/pe-master-group-missing') unless pe_master

    params = pe_master.dig('classes', PROFILE) || {}
    puts({
      '_sensitive' => { 'settings' => params.slice(*CARRIED).compact },
      'not_carried' => params.slice(*NOT_CARRIED).compact.keys.map { |p| "#{PROFILE}::#{p}" } + config_data_settings(pe_master),
    }.to_json)
  end

  def groups
    client = https
    begin
      response = client.get(GROUPS_PATH)
    rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => e
      error!("Could not reach the classifier at #{url}: #{e.message}")
    end
    error!("Classifier returned HTTP #{response.code} for #{url}: #{response.body}") unless response.is_a?(Net::HTTPSuccess)
    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      error!("Classifier returned a response that is not JSON for #{url}: #{e.message}")
    end
  end

  def https
    https = Net::HTTP.new(Puppet.settings[:certname], 4433)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    https
  rescue SystemCallError, OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError => e
    error!("Could not load this node's certificate or key to call the classifier: #{e.message}", 'peadm/certificate-error')
  end

  private

  # Code Manager entries in the group's configuration data ("Data" tab), named
  # class::parameter. Data for the profile class counts when it is an r10k or
  # Code Manager setting.
  def config_data_settings(group)
    (group['config_data'] || {}).flat_map do |klass, data|
      next [] unless data.is_a?(Hash)
      keys = if CODE_MANAGER_CLASSES.include?(klass)
               data.keys
             elsif klass == PROFILE
               data.keys.grep(%r{\A(r10k_|code_manager_)})
             else
               []
             end
      keys.map { |key| "#{klass}::#{key}" }
    end
  end

  def url
    "https://#{Puppet.settings[:certname]}:4433#{GROUPS_PATH}"
  end

  def error!(msg, kind = 'peadm/classifier-request-failed')
    puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
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
