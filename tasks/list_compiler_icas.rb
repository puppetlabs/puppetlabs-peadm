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
  HEADERS = ['COMPILER-FQDN', 'STATE', 'PROVISIONED-AT', 'NOT-AFTER', 'AUTOSIGN-STATE', 'AUTOSIGN-FINGERPRINT'].freeze

  def initialize(params, https_client: nil)
    @state_filter = params['state']
    @format = params.fetch('format', 'table')
    @https_client = https_client
  end

  def execute!
    assert_valid_state_filter!

    response = fetch_intermediate_cas
    unless response.code.to_i.between?(200, 299)
      error!("Failed to list compiler ICAs: HTTP #{response.code} - #{response.body}", 'peadm/list_compiler_icas_failed')
    end

    body = JSON.parse(response.body)
    all_icas = body.fetch('intermediate-cas')
    icas = filtered_icas(all_icas)

    if @format == 'json'
      STDOUT.puts(body.merge('intermediate-cas' => icas).to_json)
    else
      STDOUT.puts(render_table(icas, body['autosign-inconsistent'], diverging_compilers(all_icas)))
    end
    exit 0
  end

  private

  def assert_valid_state_filter!
    return if @state_filter.nil? || VALID_STATES.include?(@state_filter)
    error!("Unknown state '#{@state_filter}': must be one of #{VALID_STATES.join(', ')}", 'peadm/list_compiler_icas_invalid_state')
  end

  def fetch_intermediate_cas
    https.get('/puppet-ca/v1/intermediate-ca')
  rescue OpenSSL::SSL::SSLError => e
    error!("TLS handshake with the primary failed: #{e.message}", 'peadm/list_compiler_icas_tls_failed')
  rescue SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    error!("Failed to connect to the primary: #{e.message}", 'peadm/list_compiler_icas_connection_failed')
  end

  def error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
    exit 1
  end

  def filtered_icas(all_icas)
    return all_icas unless @state_filter
    all_icas.select { |ica| ica['state'] == @state_filter }
  end

  def render_table(icas, autosign_inconsistent, diverging_names)
    body = icas.empty? ? empty_message : rows(icas)

    return body unless autosign_inconsistent
    "#{body}\nwarning: autosign configuration is inconsistent across #{diverging_names.join(', ')}"
  end

  def empty_message
    return "no compiler ICAs match state '#{@state_filter}'" if @state_filter
    'no compiler ICAs are provisioned'
  end

  def rows(icas)
    all_rows = [HEADERS] + icas.map { |ica| row_values(ica) }
    widths = HEADERS.each_index.map { |i| all_rows.map { |row| row[i].length }.max }
    all_rows.map { |row| format_row(row, widths) }.join("\n")
  end

  def row_values(ica)
    [
      ica['compiler-fqdn'], ica['state'], ica['provisioned-at'], ica['not-after'],
      ica['autosign-state'] || '-', ica['autosign-config-fingerprint'] || '-'
    ]
  end

  def format_row(values, widths)
    values.each_with_index.map { |v, i| v.ljust(widths[i]) }.join('  ').rstrip
  end

  def diverging_compilers(icas)
    icas.select { |ica| ica['autosign-state'] == 'divergent' }.map { |ica| ica['compiler-fqdn'] }
  end

  def https
    @https_client ||= begin
      client = Net::HTTP.new(Puppet.settings[:certname], 8140)
      client.use_ssl = true
      client.open_timeout = 10
      client.read_timeout = 10
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
