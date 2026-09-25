# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/restart_ca_service'

describe RestartCaService do
  subject(:task) { described_class.new }

  let(:success_status) { instance_double('Process::Status', success?: true) }
  let(:failure_status) { instance_double('Process::Status', success?: false) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
  end

  context 'when the restart succeeds and the service becomes active' do
    it 'reports success' do
      allow(Open3).to receive(:capture3).with('systemctl', 'restart', 'pe-puppetserver').and_return(['', '', success_status])
      allow(Open3).to receive(:capture3).with('systemctl', 'is-active', 'pe-puppetserver').and_return(["active\n", '', success_status])
      expect(STDOUT).to receive(:puts).with(JSON.generate('restarted' => true))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the restart command itself fails' do
    it 'fails with the service status output' do
      allow(Open3).to receive(:capture3).with('systemctl', 'restart', 'pe-puppetserver').and_return(['', '', failure_status])
      allow(Open3).to receive(:capture3).with('systemctl', 'status', 'pe-puppetserver', '--no-pager').and_return(['inactive (dead)', '', success_status])
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/restart_ca_service_failed')
        expect(parsed['_error']['msg']).to include('inactive (dead)')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the service never becomes active' do
    it 'fails with the service status output rather than timing out silently' do
      allow(Open3).to receive(:capture3).with('systemctl', 'restart', 'pe-puppetserver').and_return(['', '', success_status])
      allow(Open3).to receive(:capture3).with('systemctl', 'is-active', 'pe-puppetserver').and_return(["failed\n", '', failure_status])
      allow(Open3).to receive(:capture3).with('systemctl', 'status', 'pe-puppetserver', '--no-pager').and_return(['Active: failed', '', success_status])
      stub_const('RestartCaService::WAIT_TIMEOUT_SECONDS', 0.05)
      stub_const('RestartCaService::POLL_INTERVAL_SECONDS', 0.01)

      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/restart_ca_service_failed')
        expect(parsed['_error']['msg']).to include('did not become active')
        expect(parsed['_error']['msg']).to include('Active: failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
