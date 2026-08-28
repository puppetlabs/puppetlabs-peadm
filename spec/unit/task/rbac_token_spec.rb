require 'spec_helper'
require_relative '../../../tasks/rbac_token'

describe RbacToken do
  subject(:rbac_token) { described_class.new(params) }

  let(:params) { { 'password' => 'supersecret', 'token_lifetime' => '1y' } }
  let(:https_dbl) { instance_double(Net::HTTP) }
  let(:request_dbl) { instance_double(Net::HTTP::Post) }

  before(:each) do
    allow(Puppet).to receive(:initialize_settings)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                    hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                    hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                    localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
    allow(File).to receive(:read).and_return('dummy-pem-contents')
    allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))

    allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
    allow(https_dbl).to receive(:use_ssl=)
    allow(https_dbl).to receive(:cert=)
    allow(https_dbl).to receive(:key=)
    allow(https_dbl).to receive(:verify_mode=)
    allow(https_dbl).to receive(:ca_file=)

    allow(Net::HTTP::Post).to receive(:new).with('/rbac-api/v1/auth/token').and_return(request_dbl)
    allow(request_dbl).to receive(:[]=)
    allow(request_dbl).to receive(:body=)
  end

  # Catches a mutation that swaps/drops a field (login, password, lifetime,
  # or label) when building the token request body, which would send the
  # wrong credentials or request parameters to the RBAC API.
  it 'builds the POST body with login, password, lifetime, and label derived from the params' do
    expect(request_dbl).to receive(:body=) do |body|
      expect(JSON.parse(body)).to eq(
        'login'    => 'admin',
        'password' => 'supersecret',
        'lifetime' => '1y',
        'label'    => 'provision-time token',
      )
    end
    success_response = instance_double(Net::HTTPOK, body: { 'token' => 'abc123' }.to_json)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(success_response)
    allow(FileUtils).to receive(:mkdir_p)
    file_dbl = instance_double(File, write: nil)
    allow(File).to receive(:open).with('/root/.puppetlabs/token', 'w').and_yield(file_dbl)

    rbac_token.execute!
  end

  # Catches a mutation that drops the `unless response.is_a? Net::HTTPSuccess`
  # guard (or the response body from the error message), which would hide a
  # failed token request instead of raising a clear error.
  it 'raises with the response body when the RBAC API responds with a non-success status' do
    failure_response = instance_double(Net::HTTPUnauthorized, body: '{"kind":"unauthorized","msg":"bad password"}')
    allow(failure_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(failure_response)

    expect { rbac_token.execute! }.to raise_error(RuntimeError, 'Error requesting token, {"kind":"unauthorized","msg":"bad password"}')
  end

  # Catches a mutation that writes the wrong content (e.g. the whole
  # response body instead of just the extracted token) or the wrong path,
  # which would leave a broken/garbage token file on disk.
  it 'extracts the token from the JSON response and writes only the token to /root/.puppetlabs/token' do
    success_response = instance_double(Net::HTTPOK, body: { 'token' => 'the-extracted-token' }.to_json)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(success_response)

    expect(FileUtils).to receive(:mkdir_p).with('/root/.puppetlabs')
    file_dbl = instance_double(File)
    expect(file_dbl).to receive(:write).with('the-extracted-token')
    expect(File).to receive(:open).with('/root/.puppetlabs/token', 'w').and_yield(file_dbl)

    rbac_token.execute!
  end
end
