# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/restore_ca_proxy_bootstrap'

describe RestoreCaProxyBootstrap do
  before(:each) do
    allow(STDOUT).to receive(:puts)
  end

  context 'with the default proxy_target' do
    subject(:task) { described_class.new({}) }

    it 'restores bootstrap.cfg and sets ca.conf to the default proxy target' do
      expect(IcaTaskHelper).to receive(:revert_bootstrap_to_proxy!).and_return(true)
      expect(IcaTaskHelper).to receive(:set_hocon_value!)
        .with(IcaTaskHelper.ca_conf_path, 'certificate-authority.proxy-target', 'primary')
      expect(STDOUT).to receive(:puts).with(JSON.generate('proxy_target' => 'primary'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'with an explicit proxy_target' do
    subject(:task) { described_class.new('proxy_target' => 'https://ica-pool.example.com') }

    it 'sets ca.conf to the given proxy target' do
      allow(IcaTaskHelper).to receive(:revert_bootstrap_to_proxy!).and_return(true)
      expect(IcaTaskHelper).to receive(:set_hocon_value!)
        .with(IcaTaskHelper.ca_conf_path, 'certificate-authority.proxy-target', 'https://ica-pool.example.com')

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when reverting bootstrap.cfg fails' do
    subject(:task) { described_class.new({}) }

    it 'fails through the _error contract' do
      allow(IcaTaskHelper).to receive(:revert_bootstrap_to_proxy!).and_raise('disk full')
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/restore_ca_proxy_bootstrap_failed')
        expect(parsed['_error']['msg']).to eq('disk full')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when bootstrap.cfg does not exist at all' do
    subject(:task) { described_class.new({}) }

    it 'fails rather than silently reporting success, since a missing config is not the same as an already-reverted compiler' do
      allow(IcaTaskHelper).to receive_messages(
        revert_bootstrap_to_proxy!: false,
        bootstrap_cfg_path: '/etc/puppetlabs/puppetserver/bootstrap.cfg',
      )
      expect(IcaTaskHelper).not_to receive(:set_hocon_value!)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/restore_ca_proxy_bootstrap_missing_config')
        expect(parsed['_error']['msg']).to include('/etc/puppetlabs/puppetserver/bootstrap.cfg')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
