# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/resolve_current_primary'

describe ResolveCurrentPrimary do
  subject(:task) { described_class.new('candidates' => candidates) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
  end

  context 'when the first candidate answers' do
    let(:candidates) { ['replica-a.example.com', 'replica-b.example.com'] }

    it 'returns that candidate without probing the rest' do
      socket = instance_double('TCPSocket', close: nil)
      expect(TCPSocket).to receive(:new).with('replica-a.example.com', IcaTaskHelper::CA_SERVICE_PORT).and_return(socket)
      expect(TCPSocket).not_to receive(:new).with('replica-b.example.com', anything)
      expect(STDOUT).to receive(:puts).with(JSON.generate(
        'primary_url' => "https://replica-a.example.com:#{IcaTaskHelper::CA_SERVICE_PORT}",
        'resolved_from' => 'replica-a.example.com',
      ))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the first candidate is unreachable but the second answers' do
    let(:candidates) { ['replica-a.example.com', 'replica-b.example.com'] }

    it 'falls through to the second candidate' do
      allow(TCPSocket).to receive(:new).with('replica-a.example.com', IcaTaskHelper::CA_SERVICE_PORT).and_raise(Errno::ECONNREFUSED)
      socket = instance_double('TCPSocket', close: nil)
      allow(TCPSocket).to receive(:new).with('replica-b.example.com', IcaTaskHelper::CA_SERVICE_PORT).and_return(socket)
      expect(STDOUT).to receive(:puts).with(JSON.generate(
        'primary_url' => "https://replica-b.example.com:#{IcaTaskHelper::CA_SERVICE_PORT}",
        'resolved_from' => 'replica-b.example.com',
      ))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when a candidate connect hangs past the timeout' do
    let(:candidates) { ['replica-a.example.com'] }

    it 'treats the timeout as unreachable rather than raising' do
      allow(TCPSocket).to receive(:new).and_raise(Timeout::Error)
      expect(STDOUT).to receive(:puts).with(JSON.generate('error' => 'no-reachable-candidate'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when no candidate answers' do
    let(:candidates) { ['replica-a.example.com', 'replica-b.example.com'] }

    it 'reports no-reachable-candidate' do
      allow(TCPSocket).to receive(:new).and_raise(Errno::ECONNREFUSED)
      expect(STDOUT).to receive(:puts).with(JSON.generate('error' => 'no-reachable-candidate'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end
end
