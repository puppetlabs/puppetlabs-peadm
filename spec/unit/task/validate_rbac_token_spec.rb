require 'spec_helper'
require_relative '../../../tasks/validate_rbac_token'

describe ValidateRbacToken do
  subject(:validate) { described_class.new(params) }

  let(:params) { { 'token_file' => '/root/.puppetlabs/token' } }
  let(:https_dbl) { instance_double(Net::HTTP) }
  let(:request_dbl) { instance_double(Net::HTTP::Post) }

  before(:each) do
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                    hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                    hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                    localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
    allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))

    allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
    allow(https_dbl).to receive(:use_ssl=)
    allow(https_dbl).to receive(:cert=)
    allow(https_dbl).to receive(:key=)
    allow(https_dbl).to receive(:verify_mode=)
    allow(https_dbl).to receive(:ca_file=)

    allow(Net::HTTP::Post).to receive(:new).with('/rbac-api/v2/auth/token/authenticate').and_return(request_dbl)
    allow(request_dbl).to receive(:[]=)
    allow(request_dbl).to receive(:body=)

    allow(File).to receive(:read).and_return('dummy-pem-contents')
    allow(File).to receive(:read).with('/root/.puppetlabs/token').and_return("the-token\n")
    allow(STDOUT).to receive(:puts)
  end

  # Catches a mutation that changes/drops the `token_file || File.join(...)`
  # fallback, which would look in the wrong place for the token when the
  # caller doesn't supply one.
  describe 'default token_file' do
    let(:params) { {} }

    it 'falls back to ~/.puppetlabs/token via Etc.getpwuid.dir when token_file is not provided' do
      allow(Etc).to receive(:getpwuid).and_return(double('pwent', dir: '/home/testuser')) # rubocop:disable RSpec/VerifiedDoubles
      expected_path = File.join('/home/testuser', '.puppetlabs', 'token')
      expect(File).to receive(:read).with(expected_path).and_return("the-token\n")

      resp = instance_double(Net::HTTPOK, code: '200')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(resp)

      expect { validate.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end
  end

  # Catches a mutation that inverts or drops the `resp.code == '200'` check,
  # which would report an invalid token as valid (or vice versa).
  it 'exits 0 and reports the token is valid when the API responds 200' do
    resp = instance_double(Net::HTTPOK, code: '200')
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(resp)

    expect(STDOUT).to receive(:puts).with('RBAC token is valid')
    expect { validate.execute! }.to raise_error(SystemExit) do |error|
      expect(error.status).to eq(0)
    end
  end

  # Catches a mutation that collapses the 401/403 branch and the generic
  # failure branch into a single message. The 401/403 message must mention
  # re-checking/refreshing the token at its file path; the generic failure
  # message must instead report the response code/kind and body message.
  # If a mutation merged these branches, one of the two distinct assertions
  # below would fail.
  describe 'non-200 responses' do
    ['401', '403'].each do |code|
      it "prints the token-refresh guidance (and exits 1) for a #{code} response" do
        resp = instance_double(Net::HTTPResponse, code: code, body: { 'kind' => 'unauthorized-token' }.to_json)
        allow(https_dbl).to receive(:request).with(request_dbl).and_return(resp)

        expect(STDOUT).to receive(:puts).with(
          "#{code} unauthorized-token: Check your API token at /root/.puppetlabs/token.\n" \
          "Please refresh your token or provide an alternate file.\n" \
          "See https://www.puppet.com/docs/pe/latest/rbac_token_auth_intro for more details.\n",
        )
        expect(STDOUT).not_to receive(:puts).with(a_string_matching(%r{Error validating token}))

        expect { validate.execute! }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    it 'prints a distinct "Error validating token" message (and exits 1) for any other non-200 code' do
      resp = instance_double(Net::HTTPResponse, code: '500', body: { 'kind' => 'server-error', 'msg' => 'boom' }.to_json)
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(resp)

      expect(STDOUT).to receive(:puts).with('Error validating token: 500 server-error')
      expect(STDOUT).to receive(:puts).with('boom')
      expect(STDOUT).not_to receive(:puts).with(a_string_matching(%r{Check your API token at}))

      expect { validate.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end
end
