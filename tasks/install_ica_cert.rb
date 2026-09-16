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
    res = https.get("/puppet-ca/v1/intermediate-ca/#{Puppet.settings[:certname]}")
    raise "No active ICA found on #{@primary_host} for this compiler: HTTP #{res.code} - #{res.body}" unless res.code == '200'
    JSON.parse(res.body).fetch('cert-pem')
  rescue JSON::ParserError => e
    raise "Malformed response fetching the active ICA certificate from #{@primary_host} (#{e.message}). Raw body: #{res.body}"
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

  def clear_ica_pool!
    path = IcaTaskHelper.ca_conf_path
    content = File.read(path)
    stripped = content.gsub(%r{^\s*ica-pool\s*[:=]\s*\[.*?\]\s*\n?}m, '')

    # The non-greedy match above stops at the first ']', which can be a literal
    # inside a quoted value (e.g. an IPv6 URL) rather than the array's real
    # close. Cheap sanity check: removing a well-formed value leaves the
    # bracket/brace balance of the file unchanged, so compare deltas before and
    # after rather than requiring the whole file to be internally balanced --
    # unrelated brackets in comments or quoted strings must not trip this.
    unless balanced?(content, stripped)
      raise 'Removing ica-pool from ca.conf produced unbalanced brackets - ' \
            'refusing to write a possibly-corrupt ca.conf; manual intervention required'
    end

    File.write(path, stripped)
  end

  def balanced?(before, after)
    before.count('[') - before.count(']') == after.count('[') - after.count(']') &&
      before.count('{') - before.count('}') == after.count('{') - after.count('}')
  end

  def restart_ca_service!
    output, status = Open3.capture2e(IcaTaskHelper::PUPPETSERVER_BIN, 'ca', 'reload')
    raise "Failed to reload CA service: #{output}" unless status.success?
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  InstallIcaCert.new(JSON.parse(STDIN.read)).execute!
end
