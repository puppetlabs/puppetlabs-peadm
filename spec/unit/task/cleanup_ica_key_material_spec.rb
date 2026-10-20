# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/cleanup_ica_key_material'

describe CleanupIcaKeyMaterial do
  subject(:task) { described_class.new }

  before(:each) do
    allow(STDOUT).to receive(:puts)
  end

  context 'when the passphrase path is configured in ca.conf and the file exists' do
    it 'removes the configured path and reports it' do
      allow(IcaTaskHelper).to receive(:get_hocon_value)
        .with(IcaTaskHelper.ca_conf_path, 'certificate-authority.ica-passphrase-path')
        .and_return('/custom/ica_passphrase')
      expect(File).to receive(:delete).with('/custom/ica_passphrase')
      expect(STDOUT).to receive(:puts).with(JSON.generate('path' => '/custom/ica_passphrase', 'removed' => true))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when ca.conf has no override and the default passphrase file is already gone' do
    it 'succeeds without treating the missing file as an error' do
      allow(IcaTaskHelper).to receive(:get_hocon_value).and_return(nil)
      allow(File).to receive(:delete).with(IcaTaskHelper::DEFAULT_ICA_PASSPHRASE_PATH).and_raise(Errno::ENOENT)
      expect(STDOUT).to receive(:puts).with(JSON.generate('path' => IcaTaskHelper::DEFAULT_ICA_PASSPHRASE_PATH, 'removed' => false))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when deleting the file fails for a reason other than it being missing' do
    it 'fails through the _error contract' do
      allow(IcaTaskHelper).to receive(:get_hocon_value).and_return(nil)
      allow(File).to receive(:delete).and_raise(Errno::EACCES, 'permission denied')
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/cleanup_ica_key_material_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
