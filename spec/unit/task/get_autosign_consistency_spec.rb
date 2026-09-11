# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/get_autosign_consistency'

describe GetAutosignConsistency do
  subject(:task) { described_class.new({}) }

  let(:https) { instance_double('Net::HTTP') }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com')
    allow(IcaTaskHelper).to receive(:primary_https_client)
      .with('primary.example.com', IcaTaskHelper::CA_SERVICE_PORT)
      .and_return(https)
  end

  context 'when the fleet autosign configuration is consistent' do
    it 'returns autosign-inconsistent => false' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'autosign-inconsistent' => false }.to_json)
      allow(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca').and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('autosign-inconsistent' => false))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the fleet autosign configuration is inconsistent' do
    it 'returns autosign-inconsistent => true' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'autosign-inconsistent' => true }.to_json)
      allow(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca').and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('autosign-inconsistent' => true))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the flag is absent from the response' do
    it 'treats it as consistent rather than raising' do
      response = instance_double('Net::HTTPResponse', code: '200', body: {}.to_json)
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('autosign-inconsistent' => false))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the primary returns an unexpected error' do
    it 'fails through the _error contract' do
      response = instance_double('Net::HTTPResponse', code: '500', body: 'internal error')
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/get_autosign_consistency_failed')
        expect(parsed['_error']['msg']).to include('HTTP 500')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
