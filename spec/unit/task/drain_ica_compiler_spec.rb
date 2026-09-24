# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/drain_ica_compiler'

describe DrainIcaCompiler do
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

  context 'when the active ICA is drained' do
    it 'sends the RBAC token and prints a success message' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'compiler-fqdn' => 'compiler-a.example.com', 'state' => 'draining' }.to_json)
      expect(https).to receive(:request) do |req|
        expect(req.path).to eq('/puppet-ca/v1/intermediate-ca/compiler-a.example.com/drain')
        expect(req['X-Authentication']).to eq('sekrit-token')
        response
      end
      expect(STDOUT).to receive(:puts).with(
        'Compiler compiler-a.example.com ICA is now draining. Proxy compilers will exclude it within the next ' \
        'pool refresh interval.',
      )

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when compiler_fqdn is not a valid certname' do
    subject(:task) { described_class.new('compiler_fqdn' => "compiler-a\r\nX-Injected: true", 'token_file' => '/home/user/.puppetlabs/token') }

    it 'fails through the _error contract without making a request' do
      expect(https).not_to receive(:request)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/drain_ica_compiler_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the ICA is not active' do
    it 'fails through the _error contract with the primary\'s 409 body' do
      response = instance_double('Net::HTTPResponse', code: '409', body: { 'error' => 'not-active', 'message' => "Intermediate CA for compiler 'compiler-a.example.com' is not active." }.to_json)
      allow(https).to receive(:request).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/drain_ica_compiler_failed')
        expect(parsed['_error']['msg']).to include('HTTP 409')
        expect(parsed['_error']['msg']).to include('not-active')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when no ICA exists for the FQDN' do
    it 'fails through the _error contract with the primary\'s 404 body' do
      response = instance_double('Net::HTTPResponse', code: '404', body: { 'error' => 'not-found', 'message' => 'No Intermediate CA found' }.to_json)
      allow(https).to receive(:request).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/drain_ica_compiler_failed')
        expect(parsed['_error']['msg']).to include('HTTP 404')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
