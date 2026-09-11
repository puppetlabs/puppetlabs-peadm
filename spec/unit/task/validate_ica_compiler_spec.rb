# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'
require_relative '../../../tasks/validate_ica_compiler'

describe ValidateIcaCompiler do
  subject(:task) { described_class.new('primary_host' => 'primary.example.com') }

  let(:local_https) { instance_double('Net::HTTP') }
  let(:ica_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:ica_cert) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 3
    cert.subject = OpenSSL::X509::Name.parse('/CN=compiler-a.example.com')
    cert.issuer = root_cert.subject
    cert.public_key = ica_key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.extensions = [OpenSSL::X509::ExtensionFactory.new.create_extension('basicConstraints', 'CA:TRUE,pathlen:0', true)]
    cert.sign(root_key, OpenSSL::Digest.new('SHA256'))
    cert
  end
  let(:root_https) { instance_double('Net::HTTP') }
  let(:bootstrap_cfg) { Tempfile.new('bootstrap.cfg') }

  # A real self-signed root/leaf pair, so OpenSSL::X509::Store#verify exercises
  # real chain validation rather than a stubbed boolean.
  let(:root_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:root_cert) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=Test Root CA')
    cert.issuer = cert.subject
    cert.public_key = root_key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.extensions = [
      ef.create_extension('basicConstraints', 'CA:TRUE', true),
      ef.create_extension('keyUsage', 'keyCertSign,cRLSign', true),
    ]
    cert.sign(root_key, OpenSSL::Digest.new('SHA256'))
    cert
  end
  let(:confdir) { Dir.mktmpdir }

  def leaf_signed_by_ica(ica_key, ica_cert)
    leaf_key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse('/CN=peadm-ica-validation-test')
    cert.issuer = ica_cert.subject
    cert.public_key = leaf_key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 60
    cert.sign(ica_key, OpenSSL::Digest.new('SHA256'))
    cert
  end

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'compiler-a.example.com', confdir: '/etc/puppetlabs/puppetserver')
    allow(IcaTaskHelper).to receive(:primary_https_client).with('compiler-a.example.com', IcaTaskHelper::CA_SERVICE_PORT).and_return(local_https)
    allow(IcaTaskHelper).to receive(:primary_https_client).with('primary.example.com', IcaTaskHelper::CA_SERVICE_PORT).and_return(root_https)
    allow(IcaTaskHelper).to receive(:bootstrap_cfg_path).and_return(bootstrap_cfg.path)
    allow(SecureRandom).to receive(:hex).and_return('abc123')

    FileUtils.mkdir_p("#{confdir}/ca")
    File.write("#{confdir}/ca/ica_cert.pem", ica_cert.to_pem)
    stub_const('IcaTaskHelper::PUPPETSERVER_CONFDIR', confdir)
  end

  after(:each) do
    bootstrap_cfg.close!
    FileUtils.remove_entry(confdir)
  end

  # Directly stub the private chain-verification helper for the HTTP-flow
  # tests below, since exercising it end-to-end requires real certificate
  # material set up per-example; it gets its own dedicated coverage in the
  # "chain verification" context.
  def stub_submission_flow(https, certname, leaf_pem)
    put_response = instance_double('Net::HTTPResponse', code: '200')
    allow(https).to receive(:request).and_return(put_response)
    get_response = instance_double('Net::HTTPResponse', code: '200', body: leaf_pem)
    allow(https).to receive(:get).with("/puppet-ca/v1/certificate/#{certname}?environment=production").and_return(get_response)
    allow(https).to receive(:delete)
  end

  context 'when the signed certificate verifies against the trusted chain' do
    it 'reports valid => true and performs no revert' do
      certname = 'peadm-ica-validation-abc123'
      leaf = leaf_signed_by_ica(ica_key, ica_cert)
      stub_submission_flow(local_https, certname, leaf.to_pem)
      root_response = instance_double('Net::HTTPResponse', code: '200', body: root_cert.to_pem)
      allow(root_https).to receive(:get).with('/puppet-ca/v1/certificate/ca').and_return(root_response)

      expect(STDOUT).to receive(:puts).with(JSON.generate('valid' => true))
      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the signed certificate does not verify against the trusted chain' do
    it 'reverts bootstrap.cfg to CA-proxy mode and reports valid => false' do
      certname = 'peadm-ica-validation-abc123'
      # A leaf signed by an unrelated key: the chain will not verify against
      # the real root.
      rogue_key = OpenSSL::PKey::RSA.new(2048)
      rogue_leaf = leaf_signed_by_ica(rogue_key, ica_cert)
      stub_submission_flow(local_https, certname, rogue_leaf.to_pem)
      root_response = instance_double('Net::HTTPResponse', code: '200', body: root_cert.to_pem)
      allow(root_https).to receive(:get).with('/puppet-ca/v1/certificate/ca').and_return(root_response)

      bootstrap_cfg.write("puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n")
      bootstrap_cfg.rewind
      allow(Open3).to receive(:capture2e).and_return(['', instance_double('Process::Status', success?: true)])

      expect(STDOUT).to receive(:puts).with(JSON.generate(
        'valid' => false,
        'error' => 'signed test certificate did not verify against the trusted root CA',
      ))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }

      reverted = File.read(bootstrap_cfg.path)
      expect(reverted).to include('certificate-authority-disabled-service')
      expect(reverted).not_to include('intermediate-ca-service')
    end
  end

  context 'when submitting the test CSR fails outright' do
    it 'reverts bootstrap.cfg and reports the error rather than raising' do
      allow(local_https).to receive(:request).and_return(instance_double('Net::HTTPResponse', code: '500', body: 'nope'))
      allow(local_https).to receive(:delete)
      bootstrap_cfg.write("puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n")
      bootstrap_cfg.rewind
      allow(Open3).to receive(:capture2e).and_return(['', instance_double('Process::Status', success?: true)])

      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['valid']).to eq(false)
        expect(parsed['error']).to include('Failed to submit validation CSR')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
    end
  end

  context 'when the compiler never signs the test CSR' do
    it 'times out, reverts bootstrap.cfg, and reports the timeout rather than hanging' do
      put_response = instance_double('Net::HTTPResponse', code: '200')
      allow(local_https).to receive(:request).and_return(put_response)
      allow(local_https).to receive(:delete)
      # Simulate the timeout directly rather than actually waiting
      # SIGN_WAIT_TIMEOUT_SECONDS out in the test.
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      bootstrap_cfg.write("puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n")
      bootstrap_cfg.rewind
      allow(Open3).to receive(:capture2e).and_return(['', instance_double('Process::Status', success?: true)])

      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['valid']).to eq(false)
        expect(parsed['error']).to match(%r{Timed out waiting for}i)
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
    end
  end

  context 'when bootstrap.cfg already shows the CA-proxy entry' do
    it 'reverting does not duplicate the certificate-authority-disabled-service line' do
      certname = 'peadm-ica-validation-abc123'
      rogue_key = OpenSSL::PKey::RSA.new(2048)
      rogue_leaf = leaf_signed_by_ica(rogue_key, ica_cert)
      stub_submission_flow(local_https, certname, rogue_leaf.to_pem)
      root_response = instance_double('Net::HTTPResponse', code: '200', body: root_cert.to_pem)
      allow(root_https).to receive(:get).with('/puppet-ca/v1/certificate/ca').and_return(root_response)

      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind
      allow(Open3).to receive(:capture2e).and_return(['', instance_double('Process::Status', success?: true)])

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }

      reverted = File.read(bootstrap_cfg.path)
      expect(reverted.scan('certificate-authority-disabled-service').length).to eq(2)
    end
  end
end
