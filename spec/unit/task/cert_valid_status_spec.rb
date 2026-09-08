require 'spec_helper'
require_relative '../../../tasks/cert_valid_status'

describe CertValidStatus do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'certname' => 'agent.example.com' } }
  let(:cert_provider_dbl) { instance_double(Puppet::X509::CertProvider, load_private_key_password: nil) }
  let(:ssl_provider_dbl) { instance_double(Puppet::SSL::SSLProvider) }

  before(:each) do
    allow(Puppet).to receive(:initialize_settings)
    allow(Puppet).to receive(:settings).and_return(instance_double(Puppet::Settings, use: nil))
    allow(Puppet::X509::CertProvider).to receive(:new).and_return(cert_provider_dbl)
    allow(Puppet::SSL::SSLProvider).to receive(:new).and_return(ssl_provider_dbl)
    allow(STDOUT).to receive(:puts)
  end

  # Catches a mutation that reads a different element of client_chain (e.g.
  # .last instead of .first -- the chain is ordered leaf-first, so .last
  # would report the CA's expiry instead of the client cert's), or that
  # reports a different attribute than not_after.
  it 'reports certificate-status valid with the client cert\'s not_after when load_context succeeds' do
    expires_at = Time.new(2030, 1, 1)
    ca_cert_dbl = instance_double(OpenSSL::X509::Certificate)
    client_cert_dbl = instance_double(OpenSSL::X509::Certificate, not_after: expires_at)
    ssl_context_dbl = instance_double(Puppet::SSL::SSLContext, client_chain: [client_cert_dbl, ca_cert_dbl])
    allow(ssl_provider_dbl).to receive(:load_context).and_return(ssl_context_dbl)

    expect(STDOUT).to receive(:puts) do |json_str|
      expect(JSON.parse(json_str)).to eq(
        'certificate-status' => 'valid',
        'reason' => "Expires - #{expires_at}",
      )
    end

    task.execute!
  end

  # Catches a mutation that swaps this branch's status string with the
  # Puppet::Error branch's ('unknown'), which would misreport an actively
  # invalid/unverifiable cert as merely "unknown" instead of "invalid".
  it 'reports certificate-status invalid when load_context raises Puppet::SSL::CertVerifyError' do
    allow(ssl_provider_dbl).to receive(:load_context)
      .and_raise(Puppet::SSL::CertVerifyError.new('certificate verify failed', nil, nil))

    expect(STDOUT).to receive(:puts) do |json_str|
      expect(JSON.parse(json_str)).to eq(
        'certificate-status' => 'invalid',
        'reason' => 'certificate verify failed',
      )
    end

    task.execute!
  end

  # Catches a mutation that reorders the rescue clauses (Puppet::SSL::CertVerifyError
  # must be rescued by the more specific clause first, since it is itself a
  # Puppet::Error) or that collapses this branch into the invalid-cert
  # handling, losing the valid/invalid/unknown three-way distinction that is
  # the entire point of this task.
  it 'reports certificate-status unknown when load_context raises a non-CertVerifyError Puppet::Error' do
    allow(ssl_provider_dbl).to receive(:load_context)
      .and_raise(Puppet::Error.new('no private key present'))

    expect(STDOUT).to receive(:puts) do |json_str|
      expect(JSON.parse(json_str)).to eq(
        'certificate-status' => 'unknown',
        'reason' => 'no private key present',
      )
    end

    task.execute!
  end

  # Catches a mutation that drops the private-key-password lookup and calls
  # load_context with no password (or a hardcoded nil), breaking support for
  # password-protected private keys.
  it 'passes the loaded private key password through to load_context' do
    allow(cert_provider_dbl).to receive(:load_private_key_password).and_return('s3cr3t')
    expect(ssl_provider_dbl).to receive(:load_context)
      .with(certname: 'agent.example.com', password: 's3cr3t')
      .and_return(instance_double(Puppet::SSL::SSLContext, client_chain: [instance_double(OpenSSL::X509::Certificate, not_after: Time.now)]))

    task.execute!
  end

  # Catches a mutation that ignores the task's own certname parameter (its
  # only documented input) and instead validates the local agent's own cert
  # unconditionally via Puppet.settings[:certname] or similar.
  it 'sources load_context\'s certname from the certname param, not a hardcoded value' do
    expect(ssl_provider_dbl).to receive(:load_context)
      .with(certname: 'agent.example.com', password: nil)
      .and_return(instance_double(Puppet::SSL::SSLContext, client_chain: [instance_double(OpenSSL::X509::Certificate, not_after: Time.now)]))

    task.execute!
  end
end
