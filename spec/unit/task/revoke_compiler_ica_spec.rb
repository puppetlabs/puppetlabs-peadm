# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/revoke_compiler_ica'

describe RevokeCompilerIca do
  subject(:task) { described_class.new('compiler_fqdn' => 'compiler-a.example.com', 'token_file' => '/home/user/.puppetlabs/token') }

  let(:https) { instance_double('Net::HTTP') }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com')
    allow(IcaTaskHelper).to receive(:primary_https_client)
      .with('primary.example.com', IcaTaskHelper::CA_SERVICE_PORT)
      .and_return(https)
    allow(IcaTaskHelper).to receive(:rbac_token).with('/home/user/.puppetlabs/token').and_return('sekrit-token')
  end

  context 'when the ICA is revoked and the CRL is updated' do
    it 'sends the RBAC token and reports the response' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'compiler-fqdn' => 'compiler-a.example.com', 'state' => 'revoked', 'crl-updated' => true }.to_json)
      expect(https).to receive(:request) do |req|
        expect(req.path).to eq('/puppet-ca/v1/intermediate-ca/compiler-a.example.com/revoke')
        expect(req['X-Authentication']).to eq('sekrit-token')
        response
      end
      expect(STDOUT).to receive(:puts).with(response.body)

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the ICA is marked revoked but the CRL splice failed' do
    it 'treats crl-updated: false as a failure' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'compiler-fqdn' => 'compiler-a.example.com', 'state' => 'revoked', 'crl-updated' => false }.to_json)
      allow(https).to receive(:request).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/revoke_compiler_ica_crl_not_updated')
        expect(parsed['_error']['msg']).to include('NOT yet invalidated')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when compiler_fqdn is not a valid certname' do
    subject(:task) { described_class.new('compiler_fqdn' => "compiler-a\r\nX-Injected: true", 'token_file' => '/home/user/.puppetlabs/token') }

    it 'fails through the _error contract without making a request' do
      expect(https).not_to receive(:request)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/revoke_compiler_ica_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the primary rejects the request' do
    it 'fails through the _error contract' do
      response = instance_double('Net::HTTPResponse', code: '404', body: { 'error' => 'not-found', 'message' => 'No Intermediate CA found' }.to_json)
      allow(https).to receive(:request).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/revoke_compiler_ica_failed')
        expect(parsed['_error']['msg']).to include('HTTP 404')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
