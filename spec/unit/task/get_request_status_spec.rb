# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/get_request_status'

describe GetRequestStatus do
  subject(:task) { described_class.new('request_id' => 'abc-123') }

  let(:https) { instance_double('Net::HTTP') }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com')
    allow(IcaTaskHelper).to receive(:primary_https_client)
      .with('primary.example.com', IcaTaskHelper::CA_SERVICE_PORT)
      .and_return(https)
  end

  context 'when the request is still pending' do
    it 'returns the parsed status map' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'state' => 'pending' }.to_json)
      allow(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca/requests/abc-123').and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('state' => 'pending'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the request has been approved' do
    it 'returns the approved state' do
      response = instance_double('Net::HTTPResponse', code: '200', body: { 'state' => 'approved' }.to_json)
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts).with(JSON.generate('state' => 'approved'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the request no longer exists' do
    it 'fails with a distinct kind so the caller can tell this apart from a connection failure' do
      response = instance_double('Net::HTTPResponse', code: '404', body: 'not found')
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/ica_request_not_found')
        expect(parsed['_error']['msg']).to include('abc-123')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the primary returns an unexpected error' do
    it 'fails through the generic _error contract' do
      response = instance_double('Net::HTTPResponse', code: '500', body: 'internal error')
      allow(https).to receive(:get).and_return(response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/get_request_status_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
