#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'open3'
require 'securerandom'
require 'timeout'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: prove a just-promoted compiler signs certificates on its own.
# Runs on the compiler. Submits a synthetic test CSR to the compiler's own
# local CA endpoint (now served by IntermediateCAService, per
# install_ica_cert), waits for it to be signed, and verifies the signed leaf
# chains to the root CA fetched from primary_host. The signing call itself
# never talks to primary_host -- only the chain verification does -- which is
# the point: it proves independence.
#
# This task always exits 0 and reports outcome via the 'valid' field, rather
# than the module's usual _error/exit-1 contract: unlike the sibling tasks,
# "the ICA doesn't actually work" is this task's designed, expected failure
# mode, not an exceptional one, and the calling plan branches on
# $validation['valid'] rather than a task error.
# Reverting bootstrap.cfg back to CA-proxy mode on ANY failure here --
# not just a failed chain verification, but also a submission error or a
# signing timeout -- is deliberate: if this task cannot even complete the
# round trip, promotion cannot be confirmed, and the promote plan's
# acceptance criteria call for failing safe back to proxy mode rather than
# leaving the compiler in an unverified ICA state.
class ValidateIcaCompiler
  TEST_CERTNAME_PREFIX = 'peadm-ica-validation'
  SIGN_WAIT_TIMEOUT_SECONDS = 30

  def initialize(params)
    @primary_host = params.fetch('primary_host')
  end

  def execute!
    certname = "#{TEST_CERTNAME_PREFIX}-#{SecureRandom.hex(6)}"
    local = IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)

    begin
      key = OpenSSL::PKey::RSA.new(2048)
      submit_test_csr(local, certname, build_csr(key, certname))
      leaf_pem = wait_for_signed_cert(local, certname)

      if chain_valid?(leaf_pem)
        STDOUT.puts({ 'valid' => true }.to_json)
      else
        safe_revert_to_proxy_mode!
        STDOUT.puts({ 'valid' => false, 'error' => 'signed test certificate did not verify against the trusted root CA' }.to_json)
      end
    ensure
      cleanup_test_cert(local, certname)
    end
    exit 0
  rescue StandardError => e
    safe_revert_to_proxy_mode!(original_error: e)
    STDOUT.puts({ 'valid' => false, 'error' => e.message }.to_json)
    exit 0
  end

  private

  def build_csr(key, certname)
    request = OpenSSL::X509::Request.new
    request.version = 0
    request.subject = OpenSSL::X509::Name.parse("/CN=#{certname}")
    request.public_key = key.public_key
    request.sign(key, OpenSSL::Digest.new('SHA256'))
    request.to_pem
  end

  def submit_test_csr(https, certname, csr_pem)
    req = Net::HTTP::Put.new("/puppet-ca/v1/certificate_request/#{certname}?environment=production")
    req['Content-Type'] = 'text/plain'
    req.body = csr_pem
    res = https.request(req)
    raise "Failed to submit validation CSR: HTTP #{res.code} - #{res.body}" unless res.code.to_i.between?(200, 299)
  end

  def wait_for_signed_cert(https, certname)
    Timeout.timeout(SIGN_WAIT_TIMEOUT_SECONDS) do
      loop do
        res = https.get("/puppet-ca/v1/certificate/#{certname}?environment=production")
        break res.body if res.code == '200'
        sleep 1
      end
    end
  rescue Timeout::Error
    raise "Timed out waiting for #{certname} to be signed by the compiler's own ICA"
  end

  def chain_valid?(leaf_pem)
    root_https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CA_SERVICE_PORT)
    root_res = root_https.get('/puppet-ca/v1/certificate/ca')
    raise "Failed to fetch root CA from #{@primary_host}: HTTP #{root_res.code}" unless root_res.code == '200'

    store = OpenSSL::X509::Store.new
    store.add_cert(OpenSSL::X509::Certificate.new(root_res.body))
    ica_cert = OpenSSL::X509::Certificate.new(File.read("#{IcaTaskHelper::PUPPETSERVER_CONFDIR}/ca/ica_cert.pem"))
    leaf_cert = OpenSSL::X509::Certificate.new(leaf_pem)

    store.verify(leaf_cert, [ica_cert])
  end

  # A failure in here must never propagate: it would either mask the
  # original_error that triggered the revert, or (with none in flight) crash
  # the task with a raw backtrace instead of the module's JSON output. Either
  # way the operator needs to see the original failure, plus a note that the
  # revert itself didn't complete, so they know to check the compiler by hand.
  def safe_revert_to_proxy_mode!(original_error: nil)
    revert_to_proxy_mode!
  rescue StandardError => revert_error
    prefix = original_error ? "#{original_error.message}; " : ''
    warn "#{prefix}additionally failed to revert bootstrap.cfg to proxy mode: #{revert_error.message}"
  end

  def revert_to_proxy_mode!
    path = IcaTaskHelper.bootstrap_cfg_path
    return unless File.exist?(path)

    lines = File.readlines(path)
    lines.reject! { |l| !l.strip.start_with?('#') && l.include?('intermediate-ca-service') }
    unless lines.any? { |l| !l.strip.start_with?('#') && l.include?('certificate-authority-disabled-service') }
      lines[-1] = "#{lines[-1]}\n" if lines.any? && !lines[-1].end_with?("\n")
      lines << "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n"
    end
    File.write(path, lines.join)

    Open3.capture2e(IcaTaskHelper::PUPPETSERVER_BIN, 'ca', 'reload')
  end

  def cleanup_test_cert(https, certname)
    https.delete("/puppet-ca/v1/certificate_status/#{certname}?environment=production")
  rescue StandardError => e
    warn "Failed to clean up validation test certificate #{certname}: #{e.message}"
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  ValidateIcaCompiler.new(JSON.parse(STDIN.read)).execute!
end
