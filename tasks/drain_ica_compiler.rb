#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'puppet'
require 'uri'

# Bolt task: begin graceful removal of a compiler's ICA by moving it from
# 'active' to 'draining'. Runs on the primary. Calls the existing
# POST /puppet-ca/v1/intermediate-ca/:fqdn/drain endpoint, which is gated on
# the certificate_authority:sign_ica RBAC permission, so an RBAC token is
# required alongside the node's own agent certificate.
class DrainIcaCompiler
  def initialize(params, https_client: nil)
    @fqdn = params['fqdn']
    @token = params['token']
    @https_client = https_client
  end

  def execute!
    assert_valid_params!

    response = post_drain
    code = response.code.to_i
    error!(*failure_for(code, response)) unless code.between?(200, 299)

    body = parse_body(response)
    STDOUT.puts(success_message(body['draining-since']))
    exit 0
  end

  private

  def assert_valid_params!
    if @fqdn.to_s.empty? || @fqdn !~ %r{\A[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\z}
      error!("Invalid or missing fqdn: '#{@fqdn}'", 'peadm/drain_ica_compiler_invalid_fqdn')
    end
    return unless @token.to_s.empty?
    error!('An RBAC token for a user with the certificate_authority:sign_ica permission is required', 'peadm/drain_ica_compiler_missing_token')
  end

  def post_drain
    request = Net::HTTP::Post.new("/puppet-ca/v1/intermediate-ca/#{URI.encode_www_form_component(@fqdn)}/drain")
    request['X-Authentication'] = @token
    https.request(request)
  rescue OpenSSL::SSL::SSLError => e
    error!("TLS handshake with the primary failed: #{e.message}", 'peadm/drain_ica_compiler_tls_failed')
  rescue SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    error!("Failed to connect to the primary: #{e.message}", 'peadm/drain_ica_compiler_connection_failed')
  end

  def failure_for(code, response)
    case code
    when 403
      ["Access denied draining compiler #{@fqdn} ICA: the token's user must hold the certificate_authority:sign_ica permission", 'peadm/drain_ica_compiler_forbidden']
    when 404
      ["No ICA found for compiler #{@fqdn}", 'peadm/drain_ica_compiler_not_found']
    when 409
      ["Compiler #{@fqdn} ICA is not in the 'active' state (already draining, revoked or decommissioned)", 'peadm/drain_ica_compiler_not_active']
    when 503
      ['The primary CA does not support intermediate CAs (filesystem storage backend)', 'peadm/drain_ica_compiler_unsupported']
    else
      ["Failed to drain compiler #{@fqdn} ICA: HTTP #{response.code} - #{response.body}", 'peadm/drain_ica_compiler_failed']
    end
  end

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    error!("Invalid response body from the primary: #{e.message}", 'peadm/drain_ica_compiler_invalid_response')
  end

  def success_message(draining_since)
    since = draining_since ? " (draining since #{draining_since})" : ''
    "Compiler #{@fqdn} ICA is now draining#{since}. " \
      'Proxy compilers will exclude it within the next pool refresh interval. ' \
      'To complete decommission, run peadm::decommission_ica_compiler.'
  end

  def error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
    exit 1
  end

  def https
    @https_client ||= build_https_client
  end

  def build_https_client
    client = Net::HTTP.new(Puppet.settings[:certname], 8140)
    client.use_ssl = true
    client.open_timeout = 10
    client.read_timeout = 10
    client.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    client.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    client.verify_mode = OpenSSL::SSL::VERIFY_PEER
    client.ca_file = Puppet.settings[:localcacert]
    client
  rescue Errno::ENOENT, Errno::EACCES, OpenSSL::X509::CertificateError, OpenSSL::PKey::RSAError => e
    error!("Failed to load this node's agent certificate/key: #{e.message}", 'peadm/drain_ica_compiler_credential_error')
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  DrainIcaCompiler.new(JSON.parse(STDIN.read)).execute!
end
