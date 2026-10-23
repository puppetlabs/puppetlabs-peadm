require 'spec_helper'
require_relative '../../../tasks/drain_ica_compiler'

describe DrainIcaCompiler do
  subject(:task) { described_class.new(params, https_client: https) }

  let(:params) { { 'fqdn' => 'compiler1.example.com', 'token' => 'sekrit' } }
  let(:https) { instance_double(Net::HTTP) }
  let(:code) { '200' }
  let(:body) do
    { 'compiler-fqdn' => 'compiler1.example.com', 'state' => 'draining', 'draining-since' => '2026-05-13T15:00:00Z' }.to_json
  end
  let(:response) { instance_double(Net::HTTPResponse, code: code, body: body) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(https).to receive(:request).and_return(response)
  end

  def expect_error(kind, status: 1)
    expect(STDOUT).to receive(:puts) do |output|
      parsed = JSON.parse(output)
      expect(parsed['_error']['kind']).to eq(kind)
      yield parsed['_error']['msg'] if block_given?
    end
    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(status) }
  end

  it 'POSTs to the drain endpoint for the fqdn with the token header' do
    expect(https).to receive(:request) do |req|
      expect(req).to be_a(Net::HTTP::Post)
      expect(req.path).to eq('/puppet-ca/v1/intermediate-ca/compiler1.example.com/drain')
      expect(req['X-Authentication']).to eq('sekrit')
      response
    end

    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
  end

  it 'prints the success message with the next step and exits 0' do
    expect(STDOUT).to receive(:puts) do |output|
      expect(output).to include('Compiler compiler1.example.com ICA is now draining')
      expect(output).to include('2026-05-13T15:00:00Z')
      expect(output).to include('Proxy compilers will exclude it within the next pool refresh interval')
      expect(output).to include('To complete decommission, run peadm::decommission_ica_compiler.')
    end

    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
  end

  context 'with a 404 response' do
    let(:code) { '404' }
    let(:body) { { 'error' => 'not-found' }.to_json }

    it 'fails non-zero saying no ICA was found' do
      expect_error('peadm/drain_ica_compiler_not_found') { |msg| expect(msg).to include('compiler1.example.com') }
    end
  end

  context 'with a 409 response' do
    let(:code) { '409' }
    let(:body) { { 'error' => 'not-active' }.to_json }

    it "fails non-zero saying the ICA is not 'active'" do
      expect_error('peadm/drain_ica_compiler_not_active') { |msg| expect(msg).to include("'active'") }
    end
  end

  context 'with a 403 response' do
    let(:code) { '403' }
    let(:body) { 'forbidden' }

    it 'fails non-zero naming the required permission' do
      expect_error('peadm/drain_ica_compiler_forbidden') { |msg| expect(msg).to include('certificate_authority:sign_ica') }
    end
  end

  context 'with a 503 response' do
    let(:code) { '503' }
    let(:body) { '{}' }

    it 'fails non-zero as unsupported' do
      expect_error('peadm/drain_ica_compiler_unsupported')
    end
  end

  context 'with a 500 response' do
    let(:code) { '500' }
    let(:body) { 'boom' }

    it 'fails non-zero including the HTTP code and body' do
      expect_error('peadm/drain_ica_compiler_failed') { |msg| expect(msg).to include('500', 'boom') }
    end
  end

  context 'with an unparseable 200 body' do
    let(:body) { 'not json' }

    it 'fails with an invalid-response error' do
      expect_error('peadm/drain_ica_compiler_invalid_response')
    end
  end

  context 'when the connection is refused' do
    before(:each) { allow(https).to receive(:request).and_raise(Errno::ECONNREFUSED) }

    it 'fails with a connection error' do
      expect_error('peadm/drain_ica_compiler_connection_failed')
    end
  end

  context 'when the TLS handshake fails' do
    before(:each) { allow(https).to receive(:request).and_raise(OpenSSL::SSL::SSLError, 'bad cert') }

    it 'fails with a TLS error' do
      expect_error('peadm/drain_ica_compiler_tls_failed') { |msg| expect(msg).to include('bad cert') }
    end
  end

  context 'without a token' do
    let(:params) { { 'fqdn' => 'compiler1.example.com' } }

    it 'fails before making any request' do
      expect(https).not_to receive(:request)
      expect_error('peadm/drain_ica_compiler_missing_token')
    end
  end

  context 'with an invalid fqdn' do
    let(:params) { { 'fqdn' => '../revoke', 'token' => 'sekrit' } }

    it 'fails before making any request' do
      expect(https).not_to receive(:request)
      expect_error('peadm/drain_ica_compiler_invalid_fqdn')
    end
  end
end
