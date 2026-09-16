#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'openssl'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: install this compiler's approved, signed ICA certificate.
# Config and service manipulation only, no cryptography: fetches the cert
# from the primary, pins this compiler into the shared ICA classifier group,
# clears ca.conf's ica-pool, swaps bootstrap.cfg from the CA-proxy service to
# IntermediateCAService, and restarts the CA service.
class InstallIcaCert
  def initialize(params)
    @primary_host = params.fetch('primary_host')
  end

  def execute!
    assert_promotable_bootstrap!

    https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CA_SERVICE_PORT)
    active_cert_pem = fetch_active_ica_cert(https)
    assert_cert_belongs_to_this_node!(active_cert_pem)

    if IcaTaskHelper.promoted_to_ica? && cert_matches_installed_file?(active_cert_pem)
      STDOUT.puts({ 'status' => 'already-installed' }.to_json)
      exit 0
    end

    classifier_https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CLASSIFIER_PORT)
    IcaTaskHelper.pin_to_ica_group!(classifier_https, Puppet.settings[:certname])

    clear_ica_pool!
    swap_bootstrap_cfg!
    restart_ca_service!

    # Written only after every step above succeeds, so its presence and
    # content are themselves the record that a promotion completed in full.
    # A run that dies between the bootstrap swap and the restart leaves
    # bootstrap.cfg already pointing at IntermediateCAService but this file
    # still missing (or holding an older cert) — the next run's comparison
    # above sees that mismatch and redoes the remaining steps, restart
    # included, instead of mistaking the partial state for done.
    FileUtils.mkdir_p(File.dirname(ica_cert_path))
    File.write(ica_cert_path, active_cert_pem)

    STDOUT.puts({ 'status' => 'installed' }.to_json)
    exit 0
  rescue StandardError => e
    warn "#{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n") if e.backtrace
    IcaTaskHelper.emit_error!(e.message, 'peadm/install_ica_cert_failed')
    exit 1
  end

  def ica_cert_path
    "#{IcaTaskHelper::PUPPETSERVER_CONFDIR}/ca/ica_cert.pem"
  end

  private

  def fetch_active_ica_cert(https)
    res = nil
    res = https.get("/puppet-ca/v1/intermediate-ca/#{Puppet.settings[:certname]}")
    raise "No active ICA found on #{@primary_host} for this compiler: HTTP #{res.code} - #{res.body}" unless res.code == '200'
    JSON.parse(res.body).fetch('cert-pem')
  rescue JSON::ParserError, KeyError => e
    raise "Malformed response fetching the active ICA certificate from #{@primary_host} (#{e.class}: #{e.message}). Raw body: #{res&.body || '<no response body>'}"
  end

  # mTLS only proves the responder holds a certificate this node's trust
  # anchor accepts, not that the cert it just handed back for installation
  # was actually issued for this node. Confirm the subject CN matches before
  # treating the response as this compiler's own ICA certificate.
  def assert_cert_belongs_to_this_node!(cert_pem)
    cert = OpenSSL::X509::Certificate.new(cert_pem)
    cn = cert.subject.to_a.find { |name, _value, _type| name == 'CN' }&.at(1)
    return if cn == Puppet.settings[:certname]
    raise "The certificate #{@primary_host} returned is for '#{cn || cert.subject}', not this node " \
          "(#{Puppet.settings[:certname]}); refusing to install a certificate that does not belong to this compiler"
  rescue OpenSSL::X509::CertificateError => e
    raise "Could not parse the certificate #{@primary_host} returned as an active ICA cert: #{e.message}"
  end

  def cert_matches_installed_file?(active_cert_pem)
    return false unless File.exist?(ica_cert_path)
    OpenSSL::X509::Certificate.new(File.read(ica_cert_path)).to_der == OpenSSL::X509::Certificate.new(active_cert_pem).to_der
  rescue OpenSSL::X509::CertificateError
    false
  end

  # Both a fresh CA-proxy compiler and one already swapped to
  # IntermediateCAService are valid starting points -- the latter is how a
  # run that crashed after the bootstrap swap but before the restart gets
  # retried. Anything else (a primary, or a node with neither service
  # entry) is refused: swapping it would leave two CA services registered.
  def assert_promotable_bootstrap!
    path = IcaTaskHelper.bootstrap_cfg_path
    return if File.exist?(path) &&
              File.readlines(path).any? do |l|
                IcaTaskHelper.active_service_line?(l, 'certificate-authority-disabled-service') ||
                IcaTaskHelper.active_service_line?(l, 'intermediate-ca-service')
              end
    raise "This node's bootstrap.cfg shows neither a CA-proxy nor an intermediate CA service entry; " \
          'refusing to modify it. Is this actually a compiler?'
  end

  def swap_bootstrap_cfg!
    assert_promotable_bootstrap!

    path = IcaTaskHelper.bootstrap_cfg_path
    lines = File.readlines(path)
    lines.reject! { |l| IcaTaskHelper.active_service_line?(l, 'certificate-authority-disabled-service') }
    unless lines.any? { |l| IcaTaskHelper.active_service_line?(l, 'intermediate-ca-service') }
      lines[-1] = "#{lines[-1]}\n" if lines.any? && !lines[-1].end_with?("\n")
      lines << "puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n"
    end
    File.write(path, lines.join)
  end

  ICA_POOL_ASSIGNMENT = %r{^[ \t]*ica-pool\s*[:=]\s*\[}.freeze

  def clear_ica_pool!
    path = IcaTaskHelper.ca_conf_path
    File.write(path, strip_ica_pool(File.read(path)))
  end

  # Removing a non-greedy match up to the first ']' is not enough: that
  # character can be a literal inside a quoted value (an IPv6 URL, for
  # instance) rather than the array's own close, so a naive strip can leave
  # an orphaned remainder of the value written into ca.conf without ever
  # tripping a bracket-count check, since the removed and orphaned text can
  # carry matching counts of their own. Scans forward from the array's
  # opening bracket instead, tracking quote state so a bracket inside a
  # quoted string is never mistaken for the array's own boundary.
  def strip_ica_pool(content)
    loop do
      match = content.match(ICA_POOL_ASSIGNMENT)
      break content unless match

      open_index = match.end(0) - 1
      close_index = matching_close_bracket_index(content, open_index)
      unless close_index
        raise 'Could not find a closing bracket for ica-pool in ca.conf - refusing to write a possibly-corrupt ca.conf; manual intervention required'
      end

      remove_through = close_index + 1
      remove_through += 1 if content[remove_through] == "\n"
      content = content[0...match.begin(0)] + content[remove_through..]
    end
  end

  def matching_close_bracket_index(content, open_index)
    depth = 1
    in_string = false
    escaped = false
    index = open_index + 1
    while index < content.length
      char = content[index]
      if in_string
        if escaped
          escaped = false # rubocop:disable Lint/UselessAssignment -- read at `if escaped` on the loop's next pass
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false # rubocop:disable Lint/UselessAssignment -- read at `if in_string` on the loop's next pass
        end
      else
        case char
        when '"' then in_string = true
        when '[' then depth += 1
        when ']'
          depth -= 1
          return index if depth.zero?
        end
      end
      index += 1
    end
    nil
  end

  # A full restart, not a reload: bootstrap.cfg (which now names
  # IntermediateCAService), the ICA private key (memory-only, decrypted at
  # that service's init), and the ICA database connection pool (built at
  # init too) are all only picked up at JVM boot. Matches the invocation
  # this repo already uses elsewhere for the same service.
  def restart_ca_service!
    output, status = Open3.capture2e('systemctl', 'restart', 'pe-puppetserver.service')
    return if status.success?

    # A compiler left with proxy config gone and no working CA is worse than
    # a failed promotion, so a bare exit code isn't enough here: capture the
    # service's own status output so the operator isn't left running the
    # command themselves just to see why it didn't come back up.
    status_output, = Open3.capture2e('systemctl', 'status', 'pe-puppetserver.service', '--no-pager')
    raise "Failed to restart the CA service: #{output}\n#{status_output}"
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  InstallIcaCert.new(JSON.parse(STDIN.read)).execute!
end
