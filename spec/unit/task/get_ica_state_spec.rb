# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/get_ica_state'

describe GetIcaState do
  subject(:task) { described_class.new('compiler_fqdn' => 'compiler-a.example.com') }

  let(:https) { instance_double('Net::HTTP') }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com')
    allow(IcaTaskHelper).to receive(:primary_https_client)
      .with('primary.example.com', IcaTaskHelper::CA_SERVICE_PORT)
      .and_return(https)
  end

  context 'when the primary has a state for the compiler' do
    it 'returns the parsed state map' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'state' => 'active' }.to_json)
      allow(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca/compiler-a.example.com').and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('state' => 'active'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the primary has never seen a request for this compiler' do
    it 'returns state => none rather than treating the 404 as an error' do
      response = instance_double('Net::HTTPResponse', code: '404', body: 'not found')
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('state' => 'none'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the primary returns an unexpected error' do
    it 'fails through the _error contract' do
      response = instance_double('Net::HTTPResponse', code: '500', body: 'internal error')
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/get_ica_state_failed')
        expect(parsed['_error']['msg']).to include('HTTP 500')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
