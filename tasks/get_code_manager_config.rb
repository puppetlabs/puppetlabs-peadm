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
# settings: the CARRIED settings of puppet_enterprise::profile::master, from
# the group's class parameters or, failing that, its configuration data. Bolt
# wraps _sensitive in Sensitive once it has parsed the output. (With --stream,
# Bolt prints the raw output first, values included.)
#
# not_carried: names only, never values, of the other Code Manager settings
# on the group: r10k_* and code_manager_* class parameters and configuration
# data of the profile class, and configuration data of the Code Manager
# classes. code_manager_auto_configure is left out because peadm::migrate
# always turns it on. Empty settings are left out.
#
# On failure, prints {"_error": {...}} and exits 1. Error messages never
# quote node group data; the only outside text they quote is an HTTP error
# body and network or certificate error messages.
class GetCodeManagerConfig
  CARRIED = ['r10k_remote', 'r10k_private_key', 'r10k_known_hosts', 'r10k_git_provider'].freeze
  PROFILE = 'puppet_enterprise::profile::master'
  PROFILE_SETTING = %r{\A(r10k_|code_manager_)}.freeze
  IGNORED = ['code_manager_auto_configure'].freeze
  CODE_MANAGER_CLASSES = ['puppet_enterprise::master::code_manager', 'puppet_enterprise::master::code_management'].freeze
  GROUPS_PATH = '/classifier-api/v1/groups'
  MAX_BODY = 500

  def execute!
    pe_master = groups.find { |group| group['name'] == 'PE Master' }
    error!("The classifier at #{url} has no 'PE Master' node group.", 'peadm/pe-master-group-missing') unless pe_master

    params = set(set(pe_master['classes'])[PROFILE])
    data = set(pe_master['config_data']).transform_values { |value| set(value) }
    profile_data = data.fetch(PROFILE, {})
    puts({
      '_sensitive' => { 'settings' => profile_data.merge(params).slice(*CARRIED) },
      'not_carried' => not_carried(params, data),
    }.to_json)
  rescue StandardError => e
    # Not e.message: some Ruby errors quote the value they failed on, which can
    # be a setting such as an r10k remote with a credential in it. Instead,
    # give the class, the method or constant name a NameError reports, and the
    # first line of this task in the backtrace (or the first line, if none is).
    missing_name = " (#{e.name})" if e.is_a?(NameError) && e.name
    backtrace = e.backtrace || []
    line = backtrace.find { |frame| frame.start_with?(__FILE__) } || backtrace.first
    error!("Unexpected error reading the Code Manager settings from #{url}: #{e.class}#{missing_name} at #{line}")
  end

  def groups
    response = request_groups
    # A non-2xx body is an error page, from the classifier or a proxy in front
    # of it, never node group data, so it is safe to show.
    error!("Classifier returned HTTP #{response.code} for #{url}: #{truncate(response.body)}") unless response.is_a?(Net::HTTPSuccess)
    node_groups(response)
  end

  # The parsed list of node groups. Errors give the response's type and size,
  # not its content: the body holds every node group's class parameters and
  # configuration data, and the parser's message quotes it.
  def node_groups(response)
    parsed = JSON.parse(response.body)
    return parsed if parsed.is_a?(Array) && parsed.all?(Hash)
    got = parsed.is_a?(Array) ? "a list holding a #{parsed.find { |group| !group.is_a?(Hash) }.class}" : "a #{parsed.class}"
    error!("Classifier returned JSON that is not a list of node groups for #{url} (got #{got}).")
  rescue JSON::ParserError
    content_type = response.content_type ? "Content-Type #{response.content_type}" : 'no Content-Type'
    error!("Classifier returned a response that is not JSON for #{url} (#{content_type}, #{response.body.to_s.bytesize} bytes).")
  end

  def request_groups
    https.get(GROUPS_PATH)
  rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => e
    error!("Could not reach the classifier at #{url}: #{e.message}")
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

  # The settings of a class that are set: a Hash without nil or empty values.
  # Anything else (no class, or data that is not a Hash) counts as no settings.
  def set(settings)
    return {} unless settings.is_a?(Hash)
    settings.reject { |_name, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
  end

  def not_carried(params, data)
    profile = (params.keys + data.fetch(PROFILE, {}).keys).uniq.grep(PROFILE_SETTING) - CARRIED - IGNORED
    code_manager = CODE_MANAGER_CLASSES.flat_map { |klass| data.fetch(klass, {}).keys.map { |key| "#{klass}::#{key}" } }
    code_manager + profile.map { |key| "#{PROFILE}::#{key}" }
  end

  def truncate(body)
    body = body.to_s
    (body.length > MAX_BODY) ? "#{body[0, MAX_BODY]}..." : body
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
