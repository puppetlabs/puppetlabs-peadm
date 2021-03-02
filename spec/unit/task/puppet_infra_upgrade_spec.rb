require 'spec_helper'
require_relative '../../../tasks/puppet_infra_upgrade'

describe PuppetInfraUpgrade do
  context 'replica' do
    let(:upgrade) do
      described_class.new('type' => 'replica',
                          'targets' => ['replica.example.com'],
                          'wait_until_connected_timeout' => 120)
    end

    it 'Returns when the command exits with an expected code' do
      status_dbl_0 = instance_double(Process::Status, exitstatus: 0)
      status_dbl_11 = instance_double(Process::Status, exitstatus: 11)
      allow(STDOUT).to receive(:puts)
      allow(upgrade).to receive(:wait_until_connected)

      allow(Open3).to receive(:capture2e).and_return(['hello world', status_dbl_0])
      expect(upgrade.execute!).to eq(nil)

      allow(Open3).to receive(:capture2e).and_return(['hello world', status_dbl_11])
      expect(upgrade.execute!).to eq(nil)
    end

    it 'Exits non-zero when the command exits with an unexpected code' do
      status_dbl_1 = instance_double('Process::Status', exitstatus: 1)
      allow(STDOUT).to receive(:puts)
      allow(upgrade).to receive(:wait_until_connected)
      allow(Open3).to receive(:capture2e).and_return(['hello world', status_dbl_1])
      expect { upgrade.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end

  # TESTS NOT IMPLEMENTED
  # context 'compiler' do
  #   let(:upgrade) do
  #     described_class.new('type' => 'compiler',
  #                         'targets' => ['compiler.example.com'],
  #                         'wait_until_connected_timeout' => 120)
  #   end
  # end
end
