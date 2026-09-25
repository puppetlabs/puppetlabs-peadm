# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/decommission_compiler_ica'

describe DecommissionCompilerIca do
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

  context 'when the draining ICA is decommissioned' do
    it 'sends the RBAC token and reports the response with no CRL field' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'compiler-fqdn' => 'compiler-a.example.com', 'state' => 'decommissioned' }.to_json)
      expect(https).to receive(:request) do |req|
        expect(req.path).to eq('/puppet-ca/v1/intermediate-ca/compiler-a.example.com/decommission')
        expect(req['X-Authentication']).to eq('sekrit-token')
        response
      end
      expect(STDOUT).to receive(:puts).with(response.body)

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when compiler_fqdn is not a valid certname' do
    subject(:task) { described_class.new('compiler_fqdn' => "compiler-a\r\nX-Injected: true", 'token_file' => '/home/user/.puppetlabs/token') }

    it 'fails through the _error contract without making a request' do
      expect(https).not_to receive(:request)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/decommission_compiler_ica_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the ICA is not draining' do
    it 'fails through the _error contract with the primary\'s 409 body' do
      response = instance_double('Net::HTTPResponse', code: '409', body: { 'error' => 'not-draining', 'message' => "Intermediate CA for compiler 'compiler-a.example.com' is not draining." }.to_json)
      allow(https).to receive(:request).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/decommission_compiler_ica_failed')
        expect(parsed['_error']['msg']).to include('HTTP 409')
        expect(parsed['_error']['msg']).to include('not-draining')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
