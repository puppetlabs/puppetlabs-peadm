#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: install this compiler's approved, signed ICA certificate.
# PE-44791 / Phase 3 plan ticket 7.3. Config and service manipulation only —
# no cryptography. Fetches the cert (spec.md sec 3.7), swaps bootstrap.cfg to
# IntermediateCAService (sec 5.4), clears ca.conf's ica-pool, pins this
# compiler into the shared ICA classifier group (sets pe_ca_ica_enabled), and
# restarts the CA service.
class InstallIcaCert
  def initialize(params)
    @primary_host = params.fetch('primary_host')
  end

  def execute!
    if IcaTaskHelper.promoted_to_ica?
      # bootstrap.cfg is swapped before the CA service is reloaded, so a run
      # that died between those two steps would otherwise be permanently stuck
      # in this branch with the service never reloaded. The reload is safe to
      # repeat, so always re-attempt it here; a failure must still surface.
      restart_ca_service!
      STDOUT.puts({ 'status' => 'already-installed' }.to_json)
      exit 0
    end

    assert_ca_proxy_bootstrap!

    https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CA_SERVICE_PORT)
    cert_pem = fetch_active_ica_cert(https)

    FileUtils.mkdir_p(File.dirname(ica_cert_path))
    File.write(ica_cert_path, cert_pem)

    classifier_https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CLASSIFIER_PORT)
    IcaTaskHelper.pin_to_ica_group!(classifier_https, Puppet.settings[:certname])

    clear_ica_pool!
    swap_bootstrap_cfg!
    restart_ca_service!

    STDOUT.puts({ 'status' => 'installed' }.to_json)
    exit 0
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/install_ica_cert_failed' } }.to_json)
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
  end

  def comment?(line)
    line.strip.start_with?('#')
  end

  # Only a CA-proxy compiler (one loading certificate-authority-disabled-service)
  # may be swapped to the intermediate CA service. Swapping any other node shape
  # -- a primary loading certificate-authority-service, for instance -- would
  # leave two CA services registered in bootstrap.cfg.
  def assert_ca_proxy_bootstrap!
    path = IcaTaskHelper.bootstrap_cfg_path
    return if File.exist?(path) &&
              File.readlines(path).any? { |l| !comment?(l) && l.include?('certificate-authority-disabled-service') }
    raise "This node's bootstrap.cfg does not show the expected CA-proxy service entry; refusing to swap. Is this actually a CA-proxy compiler?"
  end

  def swap_bootstrap_cfg!
    assert_ca_proxy_bootstrap!

    path = IcaTaskHelper.bootstrap_cfg_path
    lines = File.readlines(path)
    lines.reject! { |l| !comment?(l) && l.include?('certificate-authority-disabled-service') }
    unless lines.any? { |l| !comment?(l) && l.include?('intermediate-ca-service') }
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
