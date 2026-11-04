#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# Bolt task: report compiler ICAs approaching expiry. Runs on the primary.
# Reads the existing GET /puppet-ca/v1/intermediate-ca response and adds no
# new API surface. Exits 1 (the alert) when any active or draining ICA is inside
# the tightest threshold band, so the task can be used as a monitoring check.
#
# Exit codes: 0 = no active or draining ICA is in the tightest band; 1 = at least
# one is (the alert condition); 2 = the check could not be performed, in which
# case stdout normally carries an `_error` object whose kind starts with
# peadm/check_ica_expiry_. Exit 1 is reserved for the alert, so every failure
# (StandardError, ScriptError, SystemStackError and NoMemoryError, including a
# failure to load a library, bad stdin and unexpected exceptions) maps to exit 2.
# The libraries are therefore required inside run_from_stdin and not at the top
# of the file. Interrupt, SystemExit and signal exceptions are not mapped.
class CheckIcaExpiry
  DEFAULT_THRESHOLDS = [90, 60, 30].freeze
  CHECKED_STATES = ['active', 'draining'].freeze
  HEADERS = ['COMPILER-FQDN', 'STATE', 'NOT-AFTER', 'DAYS-REMAINING', 'BAND'].freeze
  FORMATS = ['table', 'json'].freeze
  SECONDS_PER_DAY = 86_400
  EXIT_EXPIRING = 1
  EXIT_CHECK_FAILED = 2
  MAX_ERROR_BODY = 500
  # The failure classes that are mapped to exit 2. Interrupt, SystemExit and
  # SignalException are deliberately left out.
  FAILURES = [StandardError, ScriptError, SystemStackError, NoMemoryError].freeze

  def initialize(params, https_client: nil, now: Time.now.utc)
    @thresholds = params['thresholds'] || DEFAULT_THRESHOLDS
    @format = params['format'] || 'table'
    @https_client = https_client
    @now = now
  end

  # Entry point used by the task script. Everything, including loading the
  # libraries, reading stdin and initializing Puppet settings, is inside the rescue so that a failure cannot
  # surface as Ruby's default uncaught-exception exit 1.
  def self.run_from_stdin
    load_dependencies
    Puppet.initialize_settings
    params = JSON.parse(STDIN.read)
    raise ArgumentError, 'task parameters must be a JSON object' unless params.is_a?(Hash)
    new(params).execute!
  rescue *FAILURES => e
    fail_unexpected(e)
  end

  def self.load_dependencies
    ['json', 'net/http', 'openssl', 'puppet', 'time'].each { |library| require library }
  end

  # Reports an exception nobody anticipated. Building the message calls the
  # exception's own #message, which can itself raise, so that is guarded too.
  def self.fail_unexpected(error)
    fail!("Unexpected #{error.class}: #{error_detail(error)}", 'peadm/check_ica_expiry_unexpected')
  rescue *FAILURES
    exit EXIT_CHECK_FAILED
  end

  def self.error_detail(error)
    error.message
  rescue *FAILURES
    'its message could not be read'
  end

  # Emits a structured `_error` and exits 2. The message is scrubbed to valid
  # UTF-8 so that serializing it cannot itself raise. If stdout is unwritable
  # (for example a broken pipe) there is nowhere left to report, but the exit
  # code must still be 2 and not Ruby's default 1.
  def self.fail!(msg, kind)
    begin
      write_error(msg.to_s.dup.force_encoding('UTF-8').scrub('?'), kind)
    rescue *FAILURES
      nil
    end
    exit EXIT_CHECK_FAILED
  end

  def self.write_error(text, kind)
    STDOUT.puts(error_json(text, kind))
  rescue *FAILURES
    begin
      STDOUT.puts(fallback_error_json(kind))
    rescue *FAILURES
      nil
    end
  end

  def self.error_json(text, kind)
    { '_error' => { 'msg' => text, 'kind' => kind } }.to_json
  end

  # Last resort, built by hand because it must work even if the json library
  # failed to load. The kind is always one of this file's ASCII string literals.
  def self.fallback_error_json(kind)
    %({"_error":{"msg":"error message could not be written","kind":"#{kind}"}})
  end

  def execute!
    run
  rescue *FAILURES => e
    self.class.fail_unexpected(e)
  end

  private

  def run
    assert_valid_format!
    thresholds = validated_thresholds

    response = fetch_intermediate_cas
    unless response.code.to_i.between?(200, 299)
      error!("Failed to list compiler ICAs: HTTP #{response.code} - #{printable(response.body)[0, MAX_ERROR_BODY]}", 'peadm/check_ica_expiry_failed')
    end

    all_icas = parse_icas(response)
    reported = expiring(all_icas, thresholds)

    output(all_icas, reported, thresholds)
    breached = reported.any? { |ica| ica['threshold-band'] == thresholds.min }
    exit(breached ? EXIT_EXPIRING : 0)
  end

  def assert_valid_format!
    return if FORMATS.include?(@format)
    error!("format must be one of #{FORMATS.join(', ')}, got #{@format.inspect}", 'peadm/check_ica_expiry_invalid_format')
  end

  def validated_thresholds
    unless @thresholds.is_a?(Array) && !@thresholds.empty?
      invalid_thresholds!("thresholds must be an array with at least one number of days, got #{@thresholds.inspect}")
    end
    bad = @thresholds.reject { |t| t.is_a?(Integer) && t.positive? }
    invalid_thresholds!("thresholds must be positive whole numbers of days, got #{bad.map(&:inspect).join(', ')}") unless bad.empty?
    @thresholds.uniq.sort.reverse
  end

  def invalid_thresholds!(msg)
    error!(msg, 'peadm/check_ica_expiry_invalid_thresholds')
  end

  def fetch_intermediate_cas
    https.get('/puppet-ca/v1/intermediate-ca')
  rescue OpenSSL::SSL::SSLError => e
    error!("TLS handshake with the primary failed: #{e.message}", 'peadm/check_ica_expiry_tls_failed')
  rescue SystemCallError, SocketError, IOError, Net::ProtocolError, Net::HTTPBadResponse, Timeout::Error => e
    error!("Failed to connect to the primary: #{e.message}", 'peadm/check_ica_expiry_connection_failed')
  end

  def parse_icas(response)
    body = JSON.parse(response.body)
    invalid_response!('the body must be a JSON object') unless body.is_a?(Hash)
    icas = body.fetch('intermediate-cas')
    unless icas.is_a?(Array) && icas.all? { |ica| ica.is_a?(Hash) && ica['state'].is_a?(String) }
      invalid_response!('intermediate-cas must be a list of objects that each have a state')
    end
    icas
  rescue JSON::ParserError, KeyError, TypeError => e
    invalid_response!(e.message)
  end

  def invalid_response!(detail)
    error!("Invalid response body from the primary: #{detail}", 'peadm/check_ica_expiry_invalid_response')
  end

  def expiring(all_icas, thresholds)
    all_icas.select { |ica| CHECKED_STATES.include?(ica['state']) }.filter_map do |ica|
      days = days_remaining(ica)
      band = thresholds.reverse.find { |t| days <= t }
      next unless band
      ica.merge('days-remaining' => days, 'threshold-band' => band)
    end
  end

  # Whole days remaining, rounded down; negative once the ICA has expired.
  def days_remaining(ica)
    not_after = Time.iso8601(ica['not-after'].to_s)
    ((not_after - @now) / SECONDS_PER_DAY).floor
  rescue ArgumentError
    error!("ICA for #{ica['compiler-fqdn'].inspect} has an unparseable not-after: #{ica['not-after'].inspect}", 'peadm/check_ica_expiry_invalid_response')
  end

  def output(all_icas, reported, thresholds)
    if @format == 'json'
      checked = all_icas.count { |ica| CHECKED_STATES.include?(ica['state']) }
      STDOUT.puts({ 'thresholds' => thresholds, 'total' => all_icas.size, 'checked' => checked, 'icas' => reported }.to_json)
    else
      STDOUT.puts(render_table(all_icas, reported, thresholds))
    end
  end

  def render_table(all_icas, reported, thresholds)
    return 'no compiler ICAs are registered' if all_icas.empty?
    return "no active or draining compiler ICAs expire within #{thresholds.max} days" if reported.empty?

    all_rows = [HEADERS] + reported.map { |ica| row_values(ica) }
    widths = HEADERS.each_index.map { |i| all_rows.map { |row| row[i].length }.max }
    all_rows.map { |row| format_row(row, widths) }.join("\n")
  end

  def format_row(values, widths)
    values.each_with_index.map { |v, i| v.ljust(widths[i]) }.join('  ').rstrip
  end

  def row_values(ica)
    [ica['compiler-fqdn'], ica['state'], ica['not-after'], ica['days-remaining'], ica['threshold-band']].map { |v| (v || '-').to_s }
  end

  def error!(msg, kind)
    self.class.fail!(msg, kind)
  end

  def printable(text)
    text.to_s.dup.force_encoding('UTF-8').scrub('?')
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
  rescue Errno::ENOENT, Errno::EACCES, OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError => e
    error!("Failed to load this node's agent certificate/key: #{e.message}", 'peadm/check_ica_expiry_credential_error')
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  CheckIcaExpiry.run_from_stdin
end
