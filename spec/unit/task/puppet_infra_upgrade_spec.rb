require 'spec_helper'
require_relative '../../../tasks/puppet_infra_upgrade'

describe PEAdm::Task::PuppetInfraUpgrade do
  context 'replica' do
    let(:upgrade) do
      described_class.new('type' => 'replica',
                          'targets' => ['replica.example.com'],
                          'wait_until_connected_timeout' => 120)
    end

    it 'Returns when the command exits with an expected code' do
      status_dbl_0 = double('Status', :exitstatus => 0)
      status_dbl_11 = double('Status', :exitstatus => 11)
      allow(STDOUT).to receive(:puts)
      allow(upgrade).to receive(:wait_until_connected)

      allow(Open3).to receive(:capture2e).and_return(['hello world', status_dbl_0])
      expect(upgrade.execute!).to eq(nil)

      allow(Open3).to receive(:capture2e).and_return(['hello world', status_dbl_11])
      expect(upgrade.execute!).to eq(nil)
    end

    it 'Exits non-zero when the command exits with an unexpected code' do
      status_dbl_1 = double('Status', :exitstatus => 1)
      allow(STDOUT).to receive(:puts)
      allow(upgrade).to receive(:wait_until_connected)
      allow(Open3).to receive(:capture2e).and_return(['hello world', status_dbl_1])
      expect { upgrade.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end

  context 'compiler' do
    let(:upgrade) do
      described_class.new('type' => 'compiler',
                          'targets' => ['replica.example.com'],
                          'wait_until_connected_timeout' => 120)
    end
  end
end
