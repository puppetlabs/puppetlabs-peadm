#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'puppet'

# Bolt task: list all compiler ICAs and their state. Runs on the primary.
# Presentation over the existing GET /puppet-ca/v1/intermediate-ca response;
# adds no new API surface.
class ListCompilerIcas
  VALID_STATES = ['active', 'draining', 'revoked', 'decommissioned'].freeze

  def initialize(params, https_client: nil)
    @state_filter = params['state']
    @format = params.fetch('format', 'table')
    @https_client = https_client
  end

  def execute!
    assert_valid_state_filter!

    response = https.get('/puppet-ca/v1/intermediate-ca')
    unless response.code.to_i.between?(200, 299)
      error!("Failed to list compiler ICAs: HTTP #{response.code} - #{response.body}", 'peadm/list_compiler_icas_failed')
    end

    body = JSON.parse(response.body)
    icas = filtered_icas(body)

    if @format == 'json'
      STDOUT.puts(body.merge('intermediate-cas' => icas).to_json)
    else
      STDOUT.puts(render_table(icas, body['autosign-inconsistent']))
    end
    exit 0
  end

  private

  def assert_valid_state_filter!
    return if @state_filter.nil? || VALID_STATES.include?(@state_filter)
    error!("Unknown state '#{@state_filter}': must be one of #{VALID_STATES.join(', ')}", 'peadm/list_compiler_icas_invalid_state')
  end

  def error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
    exit 1
  end

  def filtered_icas(body)
    icas = body.fetch('intermediate-cas')
    return icas unless @state_filter
    icas.select { |ica| ica['state'] == @state_filter }
  end

  def render_table(icas, autosign_inconsistent)
    return 'no compiler ICAs are provisioned' if icas.empty?

    rows = icas.map { |ica|
      [
        ica['compiler-fqdn'], ica['state'], ica['provisioned-at'], ica['not-after'],
        ica['autosign-state'] || '-', ica['autosign-config-fingerprint'] || '-'
      ].join(' ')
    }.join("\n")

    return rows unless autosign_inconsistent
    "#{rows}\nwarning: autosign configuration is inconsistent across #{diverging_compilers(icas).join(', ')}"
  end

  def diverging_compilers(icas)
    icas.select { |ica| ica['autosign-state'] == 'divergent' }.map { |ica| ica['compiler-fqdn'] }
  end

  def https
    @https_client ||= begin
      client = Net::HTTP.new(Puppet.settings[:certname], 8140)
      client.use_ssl = true
      client.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
      client.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
      client.verify_mode = OpenSSL::SSL::VERIFY_PEER
      client.ca_file = Puppet.settings[:localcacert]
      client
    end
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  ListCompilerIcas.new(JSON.parse(STDIN.read)).execute!
end
